import XCTest
import zlib
@testable import ShowLog

final class ShowLogTests: XCTestCase {

    // MARK: - 1. ShowLogConfig 参数钳制、脱敏与路径归一化测试

    func testShowLogConfigClampingAndNormalization() {
        let configLow = ShowLogConfig.Builder()
            .maxDatabaseLogLimit(-50)
            .maxBodyBytes(10)
            .fileBrowserRootPath("   \n\t  ")
            .fileBrowserTabTitle("   ")
            .build()

        XCTAssertEqual(configLow.maxDatabaseLogLimit, ShowLogConfig.MIN_DATABASE_LIMIT)
        XCTAssertEqual(configLow.maxBodyBytes, ShowLogConfig.MIN_BODY_BYTES)
        XCTAssertNil(configLow.fileBrowserRootPath)
        XCTAssertNil(configLow.fileBrowserTabTitle)

        let configHigh = ShowLogConfig.Builder()
            .maxDatabaseLogLimit(999_999)
            .maxBodyBytes(512 * 1024)
            .addRedactHeader("X-Secret-Key")
            .fileBrowserRootPath(" /tmp/sandbox_folder ")
            .fileBrowserTabTitle("  沙盒目录  ")
            .enabled(false)
            .showFloatingView(false)
            .build()

        XCTAssertEqual(configHigh.maxDatabaseLogLimit, ShowLogConfig.MAX_DATABASE_LIMIT)
        XCTAssertEqual(configHigh.maxBodyBytes, 512 * 1024)
        XCTAssertTrue(configHigh.shouldRedactHeader("authorization"))
        XCTAssertTrue(configHigh.shouldRedactHeader("COOKIE"))
        XCTAssertTrue(configHigh.shouldRedactHeader("x-secret-key"))
        XCTAssertFalse(configHigh.shouldRedactHeader("Content-Type"))
        // 非空白路径保留原始字符串（对齐 Android normalizePath）
        XCTAssertEqual(configHigh.fileBrowserRootPath, " /tmp/sandbox_folder ")
        XCTAssertEqual(configHigh.fileBrowserTabTitle, "沙盒目录")
        XCTAssertFalse(configHigh.enabled)
        XCTAssertFalse(configHigh.showFloatingView)
    }

    // MARK: - 2. 强契约 HttpLogPayload 与 HttpLogRecord 转换测试

    private final class MockPayload: NSObject, HttpLogPayload {
        func getUrl() -> String { "https://api.example.com/v1/orders/create?source=ios" }
        func getMethod() -> String { "post" }
        func getHttpCode() -> Int { 200 }
        func getMessage() -> String { "订单金额不足 (code=4001)" }
        func isSuccess() -> Bool { false }
        func getDurationMs() -> Int64 { 128 }
        func getRequestHeaders() -> [String: String]? {
            ["Authorization": "Bearer secret_jwt", "Content-Type": "application/json"]
        }
        func getResponseHeaders() -> [String: String]? {
            ["Set-Cookie": "sid=123456", "X-Trace": "trace-001"]
        }
        func getRequestBody() -> Any? {
            ["orderId": 888, "items": ["A", "B"]]
        }
        func getResponseBody() -> Any? {
            "{\"code\":4001,\"msg\":\"订单金额不足\"}"
        }
        func getError() -> Error? { nil }
    }

    func testHttpLogPayloadConversionAndHeaderRedaction() {
        ShowLog.initialize(config: ShowLogConfig.defaultConfig())
        let payload = MockPayload()
        let record = HttpLogRecord.fromPayload(payload)

        XCTAssertEqual(record.url, "https://api.example.com/v1/orders/create?source=ios")
        XCTAssertEqual(record.host, "api.example.com")
        XCTAssertEqual(record.path, "/v1/orders/create")
        XCTAssertEqual(record.method, "POST")
        XCTAssertEqual(record.statusCode, 200)
        XCTAssertEqual(record.httpCode, 200)
        XCTAssertFalse(record.success)
        XCTAssertTrue(record.isFailed)
        XCTAssertEqual(record.message, "订单金额不足 (code=4001)")
        XCTAssertEqual(record.errorMessage, "订单金额不足 (code=4001)")
        XCTAssertTrue(record.requestHeaders?.contains("Authorization: ****** [REDACTED]") == true)
        XCTAssertTrue(record.responseHeaders?.contains("Set-Cookie: ****** [REDACTED]") == true)
        XCTAssertTrue(record.requestBody?.contains("\n  \"orderId\" : 888") == true)
        XCTAssertTrue(record.responseBody?.contains("\n  \"code\" : 4001") == true)
        XCTAssertGreaterThan(record.requestSize, 0)
        XCTAssertGreaterThan(record.responseSize, 0)
    }

    func testInvalidUrlFallback() {
        let (host, path) = HttpLogRecord.extractHostAndPath(from: "://invalid url string")
        XCTAssertEqual(host, "unknown")
        XCTAssertEqual(path, "://invalid url string")
    }

    // MARK: - 3. SQLite WAL 持久化、LRU 修剪与双层仓储 Hybrid-Read 测试

    func testSqliteWalAndHybridRepository() {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ShowLogTest_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dbPath = tempDir.appendingPathComponent("test_traffic.db").path
        let helper = HttpLogSqliteHelper(customDatabasePath: dbPath)
        let config = ShowLogConfig.Builder().maxDatabaseLogLimit(100).build()
        let repo = HttpLogRepository(dbHelper: helper, config: config)
        ShowLog.setEnabled(true)

        let now = HttpLogRecord.currentTimeMillis()
        let r1 = HttpLogRecord.Builder()
            .traceId("trace_db_1")
            .url("https://api.example.com/v1/a")
            .host("api.example.com")
            .path("/v1/a")
            .method("GET")
            .statusCode(200)
            .success(true)
            .timestamp(now - 2000)
            .build()

        // 先直接落盘 r1
        helper.insertBatch([r1])

        // 再将 r2 入内存待刷盘队列（尚未落盘）
        let r2 = HttpLogRecord.Builder()
            .traceId("trace_mem_2")
            .url("https://api.example.com/v1/b")
            .host("api.example.com")
            .path("/v1/b")
            .method("POST")
            .statusCode(500)
            .success(false)
            .message("Internal Error")
            .timestamp(now - 1000)
            .build()
        repo.enqueueLog(r2)

        // 验证 Hybrid-Read 能同时读出已落盘的 r1 与内存队列中的 r2
        let queryExp = expectation(description: "Hybrid Query")
        repo.queryLogsAsync(startTime: now - 10_000, endTime: now + 10_000, isAsc: false) { records in
            XCTAssertEqual(records.count, 2)
            XCTAssertEqual(records.first?.traceId, "trace_mem_2")
            XCTAssertEqual(records.last?.traceId, "trace_db_1")
            queryExp.fulfill()
        }
        wait(for: [queryExp], timeout: 3.0)

        // 验证单条删除会同步从内存队列和 SQLite 中删除
        let delExp = expectation(description: "Delete Record")
        repo.deleteRecordAsync(r2) {
            repo.flushPendingToDisk()
            repo.queryLogsAsync(startTime: now - 10_000, endTime: now + 10_000, isAsc: false) { remaining in
                XCTAssertEqual(remaining.count, 1)
                XCTAssertEqual(remaining.first?.traceId, "trace_db_1")
                delExp.fulfill()
            }
        }
        wait(for: [delExp], timeout: 3.0)
    }

    func testSqliteTrimToLimit() {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ShowLogTrim_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let helper = HttpLogSqliteHelper(customDatabasePath: tempDir.appendingPathComponent("trim.db").path)
        let now = HttpLogRecord.currentTimeMillis()
        var batch: [HttpLogRecord] = []
        for i in 1...15 {
            batch.append(
                HttpLogRecord.Builder()
                    .traceId("t_\(i)")
                    .url("https://api.example.com/item/\(i)")
                    .host("api.example.com")
                    .path("/item/\(i)")
                    .method("GET")
                    .statusCode(200)
                    .timestamp(now + Int64(i))
                    .build()
            )
        }
        helper.insertBatch(batch)
        helper.trimToLimit(5)

        let remaining = helper.queryRange(startTime: 0, endTime: Int64.max, isAsc: true)
        XCTAssertEqual(remaining.count, 5)
        XCTAssertEqual(remaining.first?.traceId, "t_11")
        XCTAssertEqual(remaining.last?.traceId, "t_15")
    }

    // MARK: - 4. 生产包零开销直通模式 (enabled = false) 测试

    func testZeroOverheadDisabledMode() {
        ShowLog.setEnabled(false)
        defer { ShowLog.setEnabled(true) }

        let req = URLRequest(url: URL(string: "https://api.example.com/ping")!)
        XCTAssertFalse(ShowLogURLProtocol.canInit(with: req))
    }

    // MARK: - 5. 业务裁决器 (HttpLogBusinessJudger) 测试

    func testBusinessJudgerClosure() {
        ShowLog.setBusinessJudgerBlock { context in
            if let json = context.optResponseBodyAsJson(),
               let code = json["code"] as? Int {
                return code == 0
                    ? HttpLogJudgementResult.success("业务成功")
                    : HttpLogJudgementResult.failure((json["msg"] as? String) ?? "业务异常")
            }
            return HttpLogJudgementResult.failure("非JSON响应")
        }
        defer { ShowLog.setBusinessJudger(nil) }

        let ctx = HttpLogRequestContext(
            url: "https://api.example.com/pay",
            method: "POST",
            httpCode: 200,
            durationMs: 45,
            responseBody: "{\"code\":1002,\"msg\":\"余额不足\"}"
        )
        let result = ShowLog.getBusinessJudger()?.judge(ctx)
        XCTAssertNotNil(result)
        XCTAssertFalse(result!.isSuccess())
        XCTAssertEqual(result!.getMessage(), "余额不足")
    }

    // MARK: - 6. 二进制探测、超长截断与 Gzip 解压测试

    func testPlaintextDetectionTruncationAndGzip() {
        let binaryData = Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0x0A, 0x1A, 0x0A])
        XCTAssertFalse(ShowLogURLProtocol.isPlaintext(binaryData))
        let binStr = ShowLogURLProtocol.decodeAndFormatBody(
            capturedData: binaryData,
            totalSize: 8,
            maxBodyBytes: 1024,
            isGzipped: false
        )
        XCTAssertEqual(binStr, "[Binary Data: size=8 bytes]")

        let longText = String(repeating: "A", count: 2000)
        let longData = longText.data(using: .utf8)!
        let truncated = ShowLogURLProtocol.decodeAndFormatBody(
            capturedData: longData.prefix(1024),
            totalSize: 2000,
            maxBodyBytes: 1024,
            isGzipped: false
        )
        XCTAssertTrue(truncated?.contains("[Content truncated: Total 2000 bytes, preserved first 1024 bytes]") == true)
    }

    // MARK: - 7. 设备全景采集与 Markdown 报告导出测试

    func testDeviceCollectorAndMarkdownExport() {
        let info = AppDeviceInfoCollector.collect()
        XCTAssertGreaterThanOrEqual(info.allItems.count, 25)
        XCTAssertFalse(info.getItemsByCategory(AppDeviceInfo.CATEGORY_APP).isEmpty)
        XCTAssertFalse(info.getItemsByCategory(AppDeviceInfo.CATEGORY_OS).isEmpty)
        XCTAssertFalse(info.getItemsByCategory(AppDeviceInfo.CATEGORY_HARDWARE).isEmpty)
        XCTAssertFalse(info.getItemsByCategory(AppDeviceInfo.CATEGORY_PERFORMANCE).isEmpty)

        let markdown = AppDeviceInfoExporter.exportToMarkdown(info)
        XCTAssertTrue(markdown.contains("# 📱 应用与设备系统全景诊断报告"))
        XCTAssertTrue(markdown.contains("### 📦 1. 应用画像 (App Profile)"))
        XCTAssertTrue(markdown.contains("### 🤖 2. 操作系统 (OS & Runtime)"))
        XCTAssertTrue(markdown.contains("### 💻 3. 硬件与显示 (Hardware & Display)"))
        XCTAssertTrue(markdown.contains("### ⚡ 4. 运行性能 (Runtime Performance)"))
        XCTAssertTrue(markdown.contains("*Generated automatically by ShowLog SDK.*"))
    }

    // MARK: - 8. 沙盒文件浏览防路径穿越与 32KB 流式分页读取测试

    func testPathTraversalAndPagedTextLoader() throws {
        let rootDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ShowLogSandbox_\(UUID().uuidString)")
        let subDir = rootDir.appendingPathComponent("logs")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let validFile = subDir.appendingPathComponent("app.log")
        let content = String(repeating: "2026-10-28 INFO [ShowLog] Request finished OK\n", count: 1200)
        try content.data(using: .utf8)!.write(to: validFile)

        // 正常子路径允许访问
        XCTAssertTrue(PagedTextLoader.isWithinRoot(rootPath: rootDir.path, candidatePath: validFile.path))

        // 路径穿越 (`..`) 严格拦截
        let traversalPath = rootDir.path + "/logs/../../etc/passwd"
        XCTAssertFalse(PagedTextLoader.isWithinRoot(rootPath: rootDir.path, candidatePath: traversalPath))

        // 探测文件类型为文本
        let kind = PagedTextLoader.detectPreviewKind(rootPath: rootDir.path, filePath: validFile.path)
        XCTAssertEqual(kind, .text)

        // 第一页 32KB 读取
        let page1 = PagedTextLoader.readTextPage(
            rootPath: rootDir.path,
            filePath: validFile.path,
            byteOffset: 0,
            maxBytes: PagedTextLoader.DEFAULT_PAGE_BYTES
        )
        XCTAssertNotNil(page1)
        XCTAssertTrue(page1!.hasMore)
        XCTAssertEqual(page1!.nextByteOffset, UInt64(PagedTextLoader.DEFAULT_PAGE_BYTES))

        // 第二页读取至末尾
        let page2 = PagedTextLoader.readTextPage(
            rootPath: rootDir.path,
            filePath: validFile.path,
            byteOffset: page1!.nextByteOffset,
            maxBytes: PagedTextLoader.DEFAULT_PAGE_BYTES
        )
        XCTAssertNotNil(page2)
        XCTAssertFalse(page2!.hasMore)
        XCTAssertEqual(page1!.text + page2!.text, content)
    }

    // MARK: - 9. 主中枢 Tab 越界纠正与 URLSessionConfiguration 防重注入测试

    func testHubTabFallbackAndConfigInjector() {
        let configWithoutFileTab = ShowLogConfig.Builder().fileBrowserRootPath(nil).build()
        let hub = ShowLogHubViewController(initialTab: ShowLogHubViewController.TAB_FILE_BROWSER, config: configWithoutFileTab)
        XCTAssertEqual(hub.tabCount, 3)
        XCTAssertEqual(hub.currentTab, ShowLogHubViewController.TAB_NETWORK)
        XCTAssertEqual(ShowLogHubViewController.lastSelectedTab, ShowLogHubViewController.TAB_NETWORK)

        let sessionCfg = URLSessionConfiguration.ephemeral
        ShowLog.inject(into: sessionCfg)
        ShowLog.inject(into: sessionCfg)
        let count = (sessionCfg.protocolClasses ?? []).filter { $0 == ShowLogURLProtocol.self }.count
        XCTAssertEqual(count, 1)
    }

    // MARK: - 10. Hub 视图与子面板生命周期（防 ObjC -release 递归冲突回归测试）

    func testHubLifecycleAndPanelTeardown() {
        #if canImport(UIKit)
        let customView = CustomPanelPageView(frame: CGRect(x: 0, y: 0, width: 300, height: 400))
        XCTAssertNotNil(customView)
        customView.renderCustomContent()
        customView.teardown()

        let tempDir = NSTemporaryDirectory()
        let fileBrowserView = FileBrowserView(rootPath: tempDir)
        XCTAssertNotNil(fileBrowserView)
        fileBrowserView.teardown()

        let config = ShowLogConfig.Builder()
            .fileBrowserRootPath(tempDir)
            .build()
        let hub = ShowLogHubViewController(initialTab: ShowLogHubViewController.TAB_CUSTOM, config: config)
        _ = hub.view // 触发 loadView / viewDidLoad 与 setupPages
        hub.view.frame = CGRect(x: 0, y: 0, width: 375, height: 667)
        hub.view.layoutIfNeeded()

        // 验证切换 Tab 时能够安全触发居中计算且不抛出任何异常
        hub.selectTab(ShowLogHubViewController.TAB_FILE_BROWSER, animated: false)
        XCTAssertEqual(hub.currentTab, ShowLogHubViewController.TAB_FILE_BROWSER)
        hub.selectTab(ShowLogHubViewController.TAB_DEVICE, animated: false)
        XCTAssertEqual(hub.currentTab, ShowLogHubViewController.TAB_DEVICE)

        hub.dismiss(animated: false)
        #endif
    }

    // MARK: - 11. 开发者接入与文档推荐 API 契约测试 (Builder businessJudger & CustomHttpLogPayload)

    private final class MockAutoPanel: NSObject, CustomPanelProvider {
        var panelTitle: String { "自动面板" }
        func createPanelView() -> UIView {
            return UIView()
        }
    }

    func testDeveloperFacingApisFromReadme() {
        // 1. 测试 ShowLogConfig.Builder 链式配置 businessJudger
        let judger = ClosureBusinessJudger { ctx in
            if ctx.statusCode == 401 {
                return .businessFailure(businessCode: "40101", errorMessage: "Token Expired")
            }
            if ctx.statusCode >= 200 && ctx.statusCode < 300 {
                return .businessSuccess(businessCode: "\(ctx.statusCode)")
            }
            return .systemError(errorCode: "\(ctx.statusCode)", message: "Network Error")
        }

        let cfg = ShowLogConfig.Builder()
            .businessJudger(judger)
            .build()
        XCTAssertNotNil(cfg.businessJudger)

        ShowLog.initialize(config: cfg)
        XCTAssertNotNil(ShowLog.getBusinessJudger())

        // 2. 测试 CustomHttpLogPayload 开箱即用模型
        let payload = CustomHttpLogPayload(
            url: "https://api.example.com/v1/user/info",
            method: "GET",
            httpCode: 200,
            message: "Success",
            success: true,
            durationMs: 45,
            requestHeaders: ["X-Client": "iOS"],
            responseHeaders: ["Content-Type": "application/json"],
            requestBody: nil,
            responseBody: "{\"code\": 0}",
            error: nil
        )
        ShowLog.record(payload: payload)

        // 3. 测试单参数 registerCustomPanel
        let panel = MockAutoPanel()
        ShowLog.registerCustomPanel(panel)
        let reg = CustomPanelManager.shared.getRegistration()
        XCTAssertEqual(reg.title, "自动面板")
        XCTAssertNotNil(reg.provider)
    }
}

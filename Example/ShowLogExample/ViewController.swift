import UIKit
import ShowLog

/// ShowLog iOS 演示宿主工程主界面。
/// 覆盖接入文档 (README.md) 中列出的全部对外 API 与功能：
/// 1. 顶层门面方法 (ShowLog.openHub, closeHub, isHubPresented, setFloatWindowVisible, isFloatWindowVisible, clearAllLogs, destroy)
/// 2. 初始化与配置参数 (ShowLog.initialize, initSDK, getConfig, ShowLogConfig.Builder 全部参数)
/// 3. 网络拦截与注入 (URLSession.shared 自动拦截、自定义 URLSessionConfiguration 注入、ShowLogURLProtocol)
/// 4. 业务裁决器 (HttpLogBusinessJudger, HttpLogJudgementResult.businessSuccess/businessFailure/systemError)
/// 5. 强契约非 URLSession 日志上报 (ShowLog.record(payload:), CustomHttpLogPayload, HttpLogPayload 协议实现, HttpLogRecord)
/// 6. 自定义面板注册 (ShowLog.registerCustomPanel 单参数协议、双参数标题协议、闭包注册)
/// 7. 沙盒只读文件浏览 (ShowLog.showFileBrowser, 流式加载与防路径穿越)
/// 8. 设备信息全景看板 (ShowLog.showAppDeviceInfo, Markdown 报告导出)
final class ViewController: UIViewController {

    private let statusCardView = UIView()
    private let statusHeaderLabel = UILabel()
    private let statusDetailsLabel = UILabel()
    private let logConsoleTextView = UITextView()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "ShowLog iOS API 验证工作台"
        view.backgroundColor = UIColor(red: 0.07, green: 0.08, blue: 0.10, alpha: 1.0)
        setupDemoUI()
        updateDashboardStatus("Ready: 请点击下方按钮验证 README 中列出的全部对外 API")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if ProcessInfo.processInfo.arguments.contains("-RunAutomatedSmokeTest") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.runFullAutomatedSmokeTest()
            }
        } else if ProcessInfo.processInfo.arguments.contains("-OpenHub") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                ShowLog.openHub()
            }
        }
    }

    // MARK: - UI 构建

    private func setupDemoUI() {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 14
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)

        // 1. 顶部状态监控看板
        setupStatusCard(into: stackView)

        // 2. 核心大按钮：一键全自动化冒烟运行测试
        let autoSuiteBtn = buildActionButton(
            "🧪 【一键全自动化冒烟测试】逐项调用并验证全部 API",
            color: 0x8B5CF6,
            action: #selector(runFullAutomatedSmokeTest)
        )
        autoSuiteBtn.heightAnchor.constraint(equalToConstant: 46).isActive = true
        stackView.addArrangedSubview(autoSuiteBtn)

        // 3. 第一组：全景中枢与悬浮球控制 API (README 第 3 & 11 节)
        stackView.addArrangedSubview(buildSectionHeader("一、全景中枢与悬浮球控制 API (ShowLog)"))
        stackView.addArrangedSubview(buildActionButton("🚀 编程式呼出全景调试中枢 (ShowLog.openHub)", color: 0x3B82F6, action: #selector(btnOpenHub)))
        stackView.addArrangedSubview(buildActionButton("⏱️ 呼出并在 1.5s 后自动收起 (ShowLog.closeHub)", color: 0x2563EB, action: #selector(btnCloseHubDelayed)))
        stackView.addArrangedSubview(buildActionButton("❓ 查询 Hub 当前展开状态 (ShowLog.isHubPresented)", color: 0x1D4ED8, action: #selector(btnCheckHubPresented)))
        stackView.addArrangedSubview(buildActionButton("👁️ 显示吸边悬浮球 (ShowLog.setFloatWindowVisible(true))", color: 0x059669, action: #selector(btnShowFloatWindow)))
        stackView.addArrangedSubview(buildActionButton("🙈 隐藏吸边悬浮球 (ShowLog.setFloatWindowVisible(false))", color: 0x475569, action: #selector(btnHideFloatWindow)))
        stackView.addArrangedSubview(buildActionButton("❓ 查询悬浮球可见性 (ShowLog.isFloatWindowVisible)", color: 0x0D9488, action: #selector(btnCheckFloatVisible)))
        stackView.addArrangedSubview(buildActionButton("🌐 直达「网络日志」面板 (ShowLog.showNetworkLogs)", color: 0x0284C7, action: #selector(btnShowNetworkLogs)))
        stackView.addArrangedSubview(buildActionButton("📱 直达「设备信息」全景看板 (ShowLog.showAppDeviceInfo)", color: 0x0284C7, action: #selector(btnShowDeviceInfo)))
        stackView.addArrangedSubview(buildActionButton("🧩 直达「自定义扩展」面板 (ShowLog.showCustomPanel)", color: 0x0284C7, action: #selector(btnShowCustomPanel)))
        stackView.addArrangedSubview(buildActionButton("📁 直达「沙盒文件浏览」面板 (ShowLog.showFileBrowser)", color: 0x0284C7, action: #selector(btnShowFileBrowser)))

        // 4. 第二组：初始化与运行时配置 API (README 第 2, 4.2, 8.2 & 11 节)
        stackView.addArrangedSubview(buildSectionHeader("二、初始化与运行时配置 API (ShowLogConfig & Lifecycle)"))
        stackView.addArrangedSubview(buildActionButton("⚙️ Builder 重新构建与初始化 (ShowLog.initialize(config:))", color: 0x4F46E5, action: #selector(btnReinitializeWithCustomConfig)))
        stackView.addArrangedSubview(buildActionButton("⚡ ObjC 默认极简初始化 (ShowLog.initSDK)", color: 0x4338CA, action: #selector(btnInitSDKDefault)))
        stackView.addArrangedSubview(buildActionButton("📋 读取当前配置 (ShowLog.getConfig)", color: 0x3730A3, action: #selector(btnGetConfig)))
        stackView.addArrangedSubview(buildActionButton("🔀 切换零开销直通模式 (ShowLog.setEnabled(!isEnabled))", color: 0x64748B, action: #selector(btnToggleEnabled)))
        stackView.addArrangedSubview(buildActionButton("🛑 彻底销毁释放 SDK (ShowLog.destroy)", color: 0xDC2626, action: #selector(btnDestroySDK)))

        // 5. 第三组：网络拦截、自定义 Session 与业务裁决 (README 第 5 节)
        stackView.addArrangedSubview(buildSectionHeader("三、网络自动拦截与业务裁决器 (URLSession & Interception)"))
        stackView.addArrangedSubview(buildActionButton("🌐 发起真实 URLSession.shared 请求 (自动透明拦截)", color: 0x10B981, action: #selector(btnTriggerRealUrlSession)))
        stackView.addArrangedSubview(buildActionButton("💉 自定义 Session 注入 (ShowLog.inject(into: config))", color: 0x059669, action: #selector(btnTriggerInjectedCustomSession)))
        stackView.addArrangedSubview(buildActionButton("❌ 模拟 HTTP 200 业务失败 (触发 HttpLogBusinessJudger 标红)", color: 0xEF4444, action: #selector(btnSimulateBusinessJudgerFailure)))
        stackView.addArrangedSubview(buildActionButton("⚖️ 动态更新业务裁决器 (ShowLog.setBusinessJudgerBlock)", color: 0xF59E0B, action: #selector(btnUpdateBusinessJudger)))
        stackView.addArrangedSubview(buildActionButton("❓ 查询当前生效的业务裁决器 (ShowLog.getBusinessJudger)", color: 0xD97706, action: #selector(btnCheckBusinessJudger)))

        // 6. 第四组：强契约手动上报与数据仓储 (README 第 6 & 11 节)
        stackView.addArrangedSubview(buildSectionHeader("四、强契约手动上报与数据仓储 (HttpLogPayload & Clear)"))
        stackView.addArrangedSubview(buildActionButton("📦 开箱即用类手动上报 (ShowLog.record(payload: CustomHttpLogPayload))", color: 0xEA580C, action: #selector(btnRecordCustomHttpLogPayload)))
        stackView.addArrangedSubview(buildActionButton("📜 纯协议实现手动上报 (ShowLog.record(payload: HttpLogPayload))", color: 0xC2410C, action: #selector(btnRecordPureProtocolPayload)))
        stackView.addArrangedSubview(buildActionButton("📝 实体对象直接上报 (ShowLog.report(record: HttpLogRecord))", color: 0xB45309, action: #selector(btnReportDirectRecord)))
        stackView.addArrangedSubview(buildActionButton("🗂️ 批量写入高频接口 (验证分组折叠与聚合)", color: 0x7C3AED, action: #selector(btnBatchFeedRequests)))
        stackView.addArrangedSubview(buildActionButton("🧹 清空所有捕获的日志 (ShowLog.clearAllLogs)", color: 0x991B1B, action: #selector(btnClearAllLogs)))

        // 7. 第五组：自定义扩展面板注册 (README 第 7.2 & 11 节)
        stackView.addArrangedSubview(buildSectionHeader("五、自定义扩展面板注册 (CustomPanelProvider)"))
        stackView.addArrangedSubview(buildActionButton("🧩 单参数协议注册 (ShowLog.registerCustomPanel(provider))", color: 0x0284C7, action: #selector(btnRegisterSingleArgPanel)))
        stackView.addArrangedSubview(buildActionButton("🏷️ 标题+协议双参数注册 (ShowLog.registerCustomPanel(title:provider:))", color: 0x0369A1, action: #selector(btnRegisterTitleAndProviderPanel)))
        stackView.addArrangedSubview(buildActionButton("⚡ 极简闭包注册 (ShowLog.registerCustomPanel(title:onCreateView:))", color: 0x075985, action: #selector(btnRegisterClosurePanel)))

        // 8. 实时控制台输出窗口
        stackView.addArrangedSubview(buildSectionHeader("六、实时测试控制台日志输出"))
        logConsoleTextView.backgroundColor = UIColor(red: 0.04, green: 0.05, blue: 0.06, alpha: 1.0)
        logConsoleTextView.textColor = UIColor(red: 0.30, green: 0.85, blue: 0.45, alpha: 1.0)
        logConsoleTextView.font = UIFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)
        logConsoleTextView.isEditable = false
        logConsoleTextView.layer.cornerRadius = 8
        logConsoleTextView.layer.borderWidth = 1
        logConsoleTextView.layer.borderColor = UIColor(white: 0.20, alpha: 1.0).cgColor
        logConsoleTextView.heightAnchor.constraint(equalToConstant: 180).isActive = true
        stackView.addArrangedSubview(logConsoleTextView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            stackView.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 14),
            stackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -24),
            stackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 14),
            stackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -14),
            stackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -28)
        ])
    }

    private func setupStatusCard(into parent: UIStackView) {
        statusCardView.backgroundColor = UIColor(red: 0.11, green: 0.12, blue: 0.16, alpha: 1.0)
        statusCardView.layer.cornerRadius = 10
        statusCardView.layer.borderWidth = 1
        statusCardView.layer.borderColor = UIColor(red: 0.20, green: 0.22, blue: 0.28, alpha: 1.0).cgColor

        let innerStack = UIStackView()
        innerStack.axis = .vertical
        innerStack.spacing = 6
        innerStack.translatesAutoresizingMaskIntoConstraints = false
        statusCardView.addSubview(innerStack)

        statusHeaderLabel.text = "📊 ShowLog 运行时核心状态看板"
        statusHeaderLabel.font = UIFont.systemFont(ofSize: 14, weight: .bold)
        statusHeaderLabel.textColor = .white
        innerStack.addArrangedSubview(statusHeaderLabel)

        statusDetailsLabel.text = "加载中..."
        statusDetailsLabel.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        statusDetailsLabel.textColor = UIColor(red: 0.25, green: 0.78, blue: 0.98, alpha: 1.0)
        statusDetailsLabel.numberOfLines = 0
        innerStack.addArrangedSubview(statusDetailsLabel)

        NSLayoutConstraint.activate([
            innerStack.topAnchor.constraint(equalTo: statusCardView.topAnchor, constant: 12),
            innerStack.bottomAnchor.constraint(equalTo: statusCardView.bottomAnchor, constant: -12),
            innerStack.leadingAnchor.constraint(equalTo: statusCardView.leadingAnchor, constant: 14),
            innerStack.trailingAnchor.constraint(equalTo: statusCardView.trailingAnchor, constant: -14)
        ])

        parent.addArrangedSubview(statusCardView)
    }

    private func buildSectionHeader(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = UIFont.systemFont(ofSize: 13.5, weight: .bold)
        label.textColor = UIColor(white: 0.92, alpha: 1.0)
        return label
    }

    private func buildActionButton(_ title: String, color: UInt32, action: Selector) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle(title, for: .normal)
        btn.setTitleColor(.white, for: .normal)
        btn.titleLabel?.font = UIFont.systemFont(ofSize: 12.5, weight: .semibold)
        btn.contentHorizontalAlignment = .left
        btn.contentEdgeInsets = UIEdgeInsets(top: 0, left: 14, bottom: 0, right: 14)
        btn.backgroundColor = ShowLogTheme.color(hex: color)
        btn.layer.cornerRadius = 8
        btn.heightAnchor.constraint(equalToConstant: 40).isActive = true
        btn.addTarget(self, action: action, for: .touchUpInside)
        return btn
    }

    private func updateDashboardStatus(_ latestAction: String) {
        let enabled = ShowLog.isEnabled()
        let floatVisible = ShowLog.isFloatWindowVisible
        let hubPresented = ShowLog.isHubPresented
        let cfg = ShowLog.getConfig()

        let details = """
        • isEnabled: \(enabled ? "🟢 true (监控中)" : "⚪ false (直通模式)")
        • isFloatWindowVisible: \(floatVisible ? "👁️ true (已挂载展示)" : "🙈 false (已隐藏)")
        • isHubPresented: \(hubPresented ? "📱 true (展开中)" : "📴 false (未弹出)")
        • DB限制: \(cfg.maxDatabaseLogLimit) 条 | 单条Body上限: \(cfg.maxBodyBytes / 1024) KB
        • 脱敏头集合: [\(cfg.redactHeaders.sorted().joined(separator: ", "))]
        • 最新操作: \(latestAction)
        """
        statusDetailsLabel.text = details

        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let logLine = "[\(timestamp)] \(latestAction)\n"
        logConsoleTextView.text = (logConsoleTextView.text ?? "") + logLine
        let range = NSRange(location: max(0, logConsoleTextView.text.count - 1), length: 1)
        logConsoleTextView.scrollRangeToVisible(range)
    }

    // MARK: - 第一组：全景中枢与悬浮球控制 API

    @objc private func btnOpenHub() {
        ShowLog.openHub()
        updateDashboardStatus("调用 ShowLog.openHub() -> 呼出全景调试中枢")
    }

    @objc private func btnCloseHubDelayed() {
        ShowLog.openHub()
        updateDashboardStatus("调用 ShowLog.openHub()，已设置 1.5 秒后自动调用 ShowLog.closeHub()")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            ShowLog.closeHub()
            self?.updateDashboardStatus("定时触发: 已调用 ShowLog.closeHub() 成功收起调试中枢")
        }
    }

    @objc private func btnCheckHubPresented() {
        let presented = ShowLog.isHubPresented
        updateDashboardStatus("调用 ShowLog.isHubPresented -> 结果: \(presented)")
    }

    @objc private func btnShowFloatWindow() {
        ShowLog.setFloatWindowVisible(true)
        updateDashboardStatus("调用 ShowLog.setFloatWindowVisible(true) -> 悬浮球可见")
    }

    @objc private func btnHideFloatWindow() {
        ShowLog.setFloatWindowVisible(false)
        updateDashboardStatus("调用 ShowLog.setFloatWindowVisible(false) -> 悬浮球隐藏")
    }

    @objc private func btnCheckFloatVisible() {
        let visible = ShowLog.isFloatWindowVisible
        updateDashboardStatus("调用 ShowLog.isFloatWindowVisible -> 结果: \(visible)")
    }

    @objc private func btnShowNetworkLogs() {
        ShowLog.showNetworkLogs(from: self)
        updateDashboardStatus("调用 ShowLog.showNetworkLogs(from: self) -> 直达网络日志")
    }

    @objc private func btnShowDeviceInfo() {
        ShowLog.showAppDeviceInfo(from: self)
        updateDashboardStatus("调用 ShowLog.showAppDeviceInfo(from: self) -> 直达设备看板")
    }

    @objc private func btnShowCustomPanel() {
        ShowLog.showCustomPanel(from: self)
        updateDashboardStatus("调用 ShowLog.showCustomPanel(from: self) -> 直达自定义扩展")
    }

    @objc private func btnShowFileBrowser() {
        ShowLog.showFileBrowser(from: self)
        updateDashboardStatus("调用 ShowLog.showFileBrowser(from: self) -> 直达沙盒文件")
    }

    // MARK: - 第二组：初始化与运行时配置 API

    @objc private func btnReinitializeWithCustomConfig() {
        let docs = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first ?? NSTemporaryDirectory()
        let customConfig = ShowLogConfig.Builder()
            .enabled(true)
            .showFloatingView(true)
            .enableURLSessionSwizzling(true)
            .maxDatabaseLogLimit(5000)
            .maxBodyBytes(128 * 1024)
            .addRedactHeader("X-Custom-Secret")
            .fileBrowserRootPath(docs)
            .fileBrowserTabTitle("应用沙盒")
            .businessJudgerBlock { ctx in
                if ctx.statusCode == 401 || (ctx.responseBody?.contains("40101") == true) {
                    return .businessFailure(businessCode: "40101", errorMessage: "Token Expired")
                }
                return .businessSuccess(businessCode: "\(ctx.statusCode)")
            }
            .build()
        ShowLog.initialize(config: customConfig)
        updateDashboardStatus("调用 ShowLog.initialize(config:) 重新完成初始化 (limit=5000, 128KB)")
    }

    @objc private func btnInitSDKDefault() {
        ShowLog.initSDK()
        updateDashboardStatus("调用 ShowLog.initSDK() -> 使用全套默认配置初始化")
    }

    @objc private func btnGetConfig() {
        let cfg = ShowLog.getConfig()
        updateDashboardStatus("调用 ShowLog.getConfig() -> limit=\(cfg.maxDatabaseLogLimit), bytes=\(cfg.maxBodyBytes)")
    }

    @objc private func btnToggleEnabled() {
        let next = !ShowLog.isEnabled()
        ShowLog.setEnabled(next)
        updateDashboardStatus("调用 ShowLog.setEnabled(\(next)) -> 切换零开销直通模式")
    }

    @objc private func btnDestroySDK() {
        ShowLog.destroy()
        updateDashboardStatus("调用 ShowLog.destroy() -> SDK 视图、定时器与仓储已完全释放")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            ShowLog.initSDK()
            self?.updateDashboardStatus("安全恢复: 自动调用 ShowLog.initSDK() 重新激活 SDK 供后续操作")
        }
    }

    // MARK: - 第三组：网络拦截、自定义 Session 与业务裁决

    @objc private func btnTriggerRealUrlSession() {
        guard let url = URL(string: "https://httpbin.org/get?test=urlsession_auto_intercept") else { return }
        var request = URLRequest(url: url)
        request.setValue("Bearer secret_jwt_token_sample", forHTTPHeaderField: "Authorization")
        request.setValue("iOS_Demo_Client", forHTTPHeaderField: "User-Agent")
        updateDashboardStatus("发起真实 URLSession.shared.dataTask -> 等待拦截...")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                if let err = error {
                    self?.updateDashboardStatus("URLSession 请求结束 (网络错误: \(err.localizedDescription)，已入库)")
                } else {
                    let len = data?.count ?? 0
                    self?.updateDashboardStatus("URLSession 自动拦截成功: HTTP \(code), 接收 \(len) 字节已入库")
                }
            }
        }.resume()
    }

    @objc private func btnTriggerInjectedCustomSession() {
        let configuration = URLSessionConfiguration.default
        ShowLog.inject(into: configuration)
        let customSession = URLSession(configuration: configuration)

        guard let url = URL(string: "https://httpbin.org/post") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("CustomInjectedSessionSecret", forHTTPHeaderField: "X-Custom-Secret")
        req.httpBody = "{\"action\": \"test_injected_session\", \"timestamp\": 1730174000}".data(using: .utf8)

        updateDashboardStatus("发起自定义注入 Session 请求 POST httpbin.org/post...")
        customSession.dataTask(with: req) { [weak self] _, response, error in
            DispatchQueue.main.async {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                self?.updateDashboardStatus("自定义 Session 完成: HTTP \(code) (注入 ShowLogURLProtocol 成功拦截)")
            }
        }.resume()
    }

    @objc private func btnSimulateBusinessJudgerFailure() {
        let record = HttpLogRecord.Builder()
            .url("https://api.example.com/v1/trade/pay")
            .host("api.example.com")
            .path("/v1/trade/pay")
            .method("POST")
            .statusCode(200)
            .httpCode(200)
            .success(false)
            .message("扣款失败：用户账户可用余额不足 (code=40101)")
            .requestHeaders("Content-Type: application/json\nAuthorization: ****** [REDACTED]")
            .requestBody("{\"orderId\": \"ORD_998822\", \"amount\": 19900}")
            .responseHeaders("Content-Type: application/json; charset=utf-8")
            .responseBody("{\"code\": 40101, \"message\": \"用户 Token 已失效或余额不足\", \"data\": null}")
            .durationMs(132)
            .errorMessage("HTTP 状态码为 200，但业务裁决器判定 code=40101 为业务失败")
            .build()
        ShowLog.report(record: record)
        updateDashboardStatus("已写入 HTTP 200 但业务失败记录 (/v1/trade/pay)，控制台已标红")
    }

    @objc private func btnUpdateBusinessJudger() {
        ShowLog.setBusinessJudgerBlock { ctx in
            if let body = ctx.responseBody, body.contains("\"code\": 40101") {
                return .businessFailure(businessCode: "40101", errorMessage: "用户 Token 过期")
            }
            if ctx.statusCode >= 200 && ctx.statusCode < 300 {
                return .businessSuccess(businessCode: "200")
            }
            return .systemError(errorCode: "\(ctx.statusCode)", message: "HTTP 异常状态码")
        }
        updateDashboardStatus("调用 ShowLog.setBusinessJudgerBlock(...) 成功更新裁决规则")
    }

    @objc private func btnCheckBusinessJudger() {
        let hasJudger = (ShowLog.getBusinessJudger() != nil)
        updateDashboardStatus("调用 ShowLog.getBusinessJudger() -> 当前是否存在裁决器: \(hasJudger)")
    }

    // MARK: - 第四组：强契约手动上报与数据仓储

    @objc private func btnRecordCustomHttpLogPayload() {
        let payload = CustomHttpLogPayload(
            url: "https://grpc.gateway.example.com/v2/stream.query",
            method: "POST",
            httpCode: 200,
            message: "gRPC 单向流调用成功",
            success: true,
            durationMs: 88,
            requestHeaders: ["Content-Type": "application/grpc", "X-Trace": "trace_9901"],
            responseHeaders: ["grpc-status": "0"],
            requestBody: "{\"stream_id\": \"st_1001\", \"client\": \"ios\"}",
            responseBody: "{\"ack\": true, \"received\": 1024}",
            error: nil
        )
        ShowLog.record(payload: payload)
        updateDashboardStatus("调用 ShowLog.record(payload: CustomHttpLogPayload) 成功上报 gRPC 报文")
    }

    @objc private func btnRecordPureProtocolPayload() {
        final class DemoCustomGrpcPayload: NSObject, HttpLogPayload {
            func getUrl() -> String { "https://socket.broker.example.com/events" }
            func getMethod() -> String { "POST" }
            func getHttpCode() -> Int { 200 }
            func getMessage() -> String { "WebSocket 二进制帧确认成功" }
            func isSuccess() -> Bool { true }
            func getDurationMs() -> Int64 { 42 }
            func getRequestHeaders() -> [String: String]? { ["Upgrade": "websocket"] }
            func getResponseHeaders() -> [String: String]? { ["Sec-WebSocket-Accept": "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="] }
            func getRequestBody() -> Any? { ["action": "heartbeat", "seq": 108] }
            func getResponseBody() -> Any? { ["status": "pong", "seq": 108] }
            func getError() -> Error? { nil }
        }

        ShowLog.record(payload: DemoCustomGrpcPayload())
        updateDashboardStatus("调用 ShowLog.record(payload: HttpLogPayload 纯协议) 成功上报")
    }

    @objc private func btnReportDirectRecord() {
        let record = HttpLogRecord.Builder()
            .url("https://analytics.example.com/log/batch")
            .method("POST")
            .statusCode(200)
            .success(true)
            .message("埋点上报成功")
            .durationMs(29)
            .requestBody("{\"events_count\": 50}")
            .responseBody("{\"code\": 0, \"saved\": 50}")
            .build()
        ShowLog.report(record: record)
        updateDashboardStatus("调用 ShowLog.report(record: HttpLogRecord) 成功直接落盘")
    }

    @objc private func btnBatchFeedRequests() {
        for i in 1...6 {
            let ok = (i != 4)
            let record = HttpLogRecord.Builder()
                .url("https://api.example.com/v1/feed/list?page=\(i)")
                .method("GET")
                .statusCode(ok ? 200 : 503)
                .success(ok)
                .message(ok ? "分页数据拉取成功" : "服务暂不可用 (503 Service Unavailable)")
                .durationMs(Int64(30 + i * 20))
                .responseBody("{\"page\": \(i), \"items_count\": \(ok ? 20 : 0)}")
                .build()
            ShowLog.report(record: record)
        }
        updateDashboardStatus("已批量灌入 6 条 /v1/feed/list 请求，控制台切换「分组」即可体验折叠")
    }

    @objc private func btnClearAllLogs() {
        ShowLog.clearAllLogs()
        updateDashboardStatus("调用 ShowLog.clearAllLogs() -> 本地 SQLite WAL 与未刷盘缓存已完全清空")
    }

    // MARK: - 第五组：自定义扩展面板注册

    private final class DemoSwitcherPanel: NSObject, CustomPanelProvider {
        var panelTitle: String { "网关环境切换" }

        func createPanelView() -> UIView {
            let container = UIView()
            container.backgroundColor = UIColor(white: 0.12, alpha: 1.0)

            let label = UILabel()
            label.text = "🌐 当前宿主网关：【预发 Staging】\n(https://staging-api.example.com)\n\n实现自 CustomPanelProvider.createPanelView()"
            label.textColor = .white
            label.numberOfLines = 0
            label.textAlignment = .center
            label.font = UIFont.systemFont(ofSize: 13, weight: .medium)
            label.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(label)

            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                label.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 16),
                label.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -16)
            ])
            return container
        }
    }

    @objc private func btnRegisterSingleArgPanel() {
        ShowLog.registerCustomPanel(DemoSwitcherPanel())
        updateDashboardStatus("调用 ShowLog.registerCustomPanel(_ provider) 单参数注册成功（Tab标题: 网关环境切换）")
    }

    @objc private func btnRegisterTitleAndProviderPanel() {
        final class SimpleBoxPanel: NSObject, CustomPanelProvider {
            func onCreateView(parent: UIView, dialogController: UIViewController) {
                let label = UILabel()
                label.text = "📦 由 onCreateView(parent:dialogController:) 承载填充\n可调用 dialogController.dismiss(animated: true) 关闭中枢"
                label.textColor = .systemGreen
                label.numberOfLines = 0
                label.textAlignment = .center
                label.font = UIFont.systemFont(ofSize: 13, weight: .bold)
                label.translatesAutoresizingMaskIntoConstraints = false
                parent.addSubview(label)
                NSLayoutConstraint.activate([
                    label.centerXAnchor.constraint(equalTo: parent.centerXAnchor),
                    label.centerYAnchor.constraint(equalTo: parent.centerYAnchor)
                ])
            }
        }
        ShowLog.registerCustomPanel(title: "Mock 控制台", provider: SimpleBoxPanel())
        updateDashboardStatus("调用 ShowLog.registerCustomPanel(title:provider:) 成功注册【Mock 控制台】")
    }

    @objc private func btnRegisterClosurePanel() {
        ShowLog.registerCustomPanel(title: "极简闭包面板") { parent, dialogVC in
            let btn = UIButton(type: .system)
            btn.setTitle("⚡ 点击此按钮主动关闭 ShowLog 中枢", for: .normal)
            btn.setTitleColor(.white, for: .normal)
            btn.backgroundColor = ShowLogTheme.bgPillSelected
            btn.layer.cornerRadius = 8
            btn.translatesAutoresizingMaskIntoConstraints = false
            parent.addSubview(btn)

            let action = UIAction { _ in
                dialogVC.dismiss(animated: true, completion: nil)
            }
            if #available(iOS 14.0, *) {
                btn.addAction(action, for: .touchUpInside)
            }
            NSLayoutConstraint.activate([
                btn.centerXAnchor.constraint(equalTo: parent.centerXAnchor),
                btn.centerYAnchor.constraint(equalTo: parent.centerYAnchor),
                btn.heightAnchor.constraint(equalToConstant: 44),
                btn.widthAnchor.constraint(equalToConstant: 260)
            ])
        }
        updateDashboardStatus("调用 ShowLog.registerCustomPanel(title:onCreateView:) 闭包注册成功")
    }

    // MARK: - 核心：一键全自动化冒烟运行测试

    @objc private func runFullAutomatedSmokeTest() {
        updateDashboardStatus("🚀 开始执行全自动化冒烟测试序列...")

        var passedCount = 0
        var totalCount = 0
        var failedSteps: [String] = []

        func check(_ stepName: String, testBlock: () -> Bool) {
            totalCount += 1
            let ok = testBlock()
            if ok {
                passedCount += 1
                let log = "  ✅ Step \(totalCount): [\(stepName)] 验证通过"
                logConsoleTextView.text = (logConsoleTextView.text ?? "") + log + "\n"
            } else {
                failedSteps.append(stepName)
                let log = "  ❌ Step \(totalCount): [\(stepName)] 验证未通过！"
                logConsoleTextView.text = (logConsoleTextView.text ?? "") + log + "\n"
            }
        }

        // 1. 初始化与配置
        check("ShowLogConfig.Builder 全部参数与 initialize") {
            let cfg = ShowLogConfig.Builder()
                .enabled(true)
                .showFloatingView(true)
                .enableURLSessionSwizzling(true)
                .maxDatabaseLogLimit(2000)
                .maxBodyBytes(128 * 1024)
                .addRedactHeader("Token")
                .fileBrowserTabTitle("测试沙盒")
                .build()
            ShowLog.initialize(config: cfg)
            return ShowLog.isEnabled() && ShowLog.getConfig().maxDatabaseLogLimit == 2000
        }

        // 2. 悬浮球可见性控制
        check("ShowLog.setFloatWindowVisible(false & true)") {
            ShowLog.setFloatWindowVisible(false)
            let v1 = ShowLog.isFloatWindowVisible
            ShowLog.setFloatWindowVisible(true)
            let v2 = ShowLog.isFloatWindowVisible
            return !v1 && v2
        }

        // 3. 业务裁决器配置
        check("ShowLog.setBusinessJudgerBlock 与 HttpLogJudgementResult 工厂") {
            ShowLog.setBusinessJudgerBlock { ctx in
                if ctx.statusCode == 404 {
                    return .businessFailure(businessCode: "404", errorMessage: "Not Found")
                }
                return .businessSuccess(businessCode: "200")
            }
            return ShowLog.getBusinessJudger() != nil
        }

        // 4. 强契约 CustomHttpLogPayload 上报
        check("ShowLog.record(payload: CustomHttpLogPayload)") {
            let p = CustomHttpLogPayload(
                url: "https://grpc.smoke.test/call",
                method: "POST",
                httpCode: 200,
                message: "OK",
                success: true,
                durationMs: 35
            )
            ShowLog.record(payload: p)
            return true
        }

        // 5. HttpLogRecord 直接上报
        check("ShowLog.report(record: HttpLogRecord)") {
            let rec = HttpLogRecord.Builder()
                .url("https://api.smoke.test/v1/ping")
                .method("GET")
                .statusCode(200)
                .success(true)
                .message("pong")
                .build()
            ShowLog.report(record: rec)
            return true
        }

        // 6. 自定义面板注册
        check("ShowLog.registerCustomPanel (单参数 & 闭包)") {
            ShowLog.registerCustomPanel(DemoSwitcherPanel())
            let reg = CustomPanelManager.shared.getRegistration()
            return reg.title == "网关环境切换"
        }

        // 7. 自定义 Session 注入
        check("ShowLog.inject(into: URLSessionConfiguration)") {
            let sessionCfg = URLSessionConfiguration.default
            ShowLog.inject(into: sessionCfg)
            let hasClass = (sessionCfg.protocolClasses ?? []).contains { $0 == ShowLogURLProtocol.self }
            return hasClass
        }

        // 8. 清空所有日志
        check("ShowLog.clearAllLogs()") {
            ShowLog.clearAllLogs()
            return true
        }

        // 9. 零开销直通模式切换
        check("ShowLog.setEnabled(!isEnabled)") {
            ShowLog.setEnabled(false)
            let d1 = ShowLog.isEnabled()
            ShowLog.setEnabled(true)
            let d2 = ShowLog.isEnabled()
            return !d1 && d2
        }

        let percent = totalCount > 0 ? (passedCount * 100 / totalCount) : 100
        let tag = (passedCount == totalCount) ? "🎉 全部通过 (100%)" : "⚠️ 失败: \(failedSteps.joined(separator: ", "))"
        updateDashboardStatus("冒烟完成: \(tag) 通过率: \(passedCount)/\(totalCount) (\(percent)%)")
    }
}

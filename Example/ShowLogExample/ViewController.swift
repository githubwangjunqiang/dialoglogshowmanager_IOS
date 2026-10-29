import UIKit
import ShowLog

/// ShowLog iOS 演示宿主工程主界面。
/// 完整演示：
/// 1. URLSession 自动拦截（2xx 成功请求、HTTP 200 但业务 code != 0 被裁决为失败、404/500 异常请求、超时失败）；
/// 2. 强契约 `HttpLogPayload` 手动上报（模拟第三方/自定义 C++ 网络库）；
/// 3. 一键唤起全景调试中枢与直达各个子面板（网络日志 / 设备信息 / 自定义扩展 / 沙盒文件浏览）；
/// 4. 动态开关 `ShowLog.setEnabled(_:)` 验证生产包零开销直通模式。
final class ViewController: UIViewController {

    private let statusLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "ShowLog iOS 演示中枢"
        view.backgroundColor = UIColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1.0)
        setupDemoUI()
    }

    private func setupDemoUI() {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)

        statusLabel.text = "✅ ShowLog 已启动（右下角可拖拽 LOG 悬浮球，点击任意按钮体验）"
        statusLabel.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        statusLabel.textColor = UIColor(red: 0.22, green: 0.74, blue: 0.97, alpha: 1.0)
        statusLabel.numberOfLines = 0
        stackView.addArrangedSubview(statusLabel)

        stackView.addArrangedSubview(buildSectionHeader("一、快速呼出 ShowLog 全景调试中枢"))
        stackView.addArrangedSubview(buildActionButton("🚀 打开全景调试中枢 (ShowLog.show)", color: 0x3B82F6, action: #selector(openHubDefault)))
        stackView.addArrangedSubview(buildActionButton("🌐 直达「网络日志」面板", color: 0x0EA5E9, action: #selector(openNetworkTab)))
        stackView.addArrangedSubview(buildActionButton("📱 直达「设备信息」全景看板", color: 0x0EA5E9, action: #selector(openDeviceTab)))
        stackView.addArrangedSubview(buildActionButton("🧩 直达「自定义扩展」面板", color: 0x0EA5E9, action: #selector(openCustomTab)))
        stackView.addArrangedSubview(buildActionButton("📁 直达「沙盒文件浏览」面板", color: 0x0EA5E9, action: #selector(openFileBrowserTab)))

        stackView.addArrangedSubview(buildSectionHeader("二、模拟网络请求与上报（体验列表/分组/cURL）"))
        stackView.addArrangedSubview(buildActionButton("✅ 模拟业务成功请求 (POST /v1/user/login)", color: 0x22C55E, action: #selector(simulateSuccessRequest)))
        stackView.addArrangedSubview(buildActionButton("❌ 模拟 HTTP 200 但业务失败 (code=4001 余额不足)", color: 0xEF4444, action: #selector(simulateBusinessFailRequest)))
        stackView.addArrangedSubview(buildActionButton("📦 批量灌入同接口高频调用 (体验分组折叠)", color: 0x6366F1, action: #selector(simulateBatchGroupRequests)))
        stackView.addArrangedSubview(buildActionButton("📝 强契约 HttpLogPayload 手动上报演示", color: 0xF59E0B, action: #selector(simulateManualPayloadReport)))
        stackView.addArrangedSubview(buildActionButton("🌐 发起真实 URLSession 请求 (httpbin.org)", color: 0x14B8A6, action: #selector(triggerRealURLSessionRequest)))

        stackView.addArrangedSubview(buildSectionHeader("三、生产环境零开销开关控制"))
        stackView.addArrangedSubview(buildActionButton("🔀 切换 ShowLog.setEnabled(!isEnabled)", color: 0x475569, action: #selector(toggleSDKEnabled)))

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            stackView.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 16),
            stackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -24),
            stackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -16),
            stackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -32)
        ])
    }

    private func buildSectionHeader(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = UIFont.systemFont(ofSize: 14, weight: .bold)
        label.textColor = .white
        return label
    }

    private func buildActionButton(_ title: String, color: UInt32, action: Selector) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle(title, for: .normal)
        btn.setTitleColor(.white, for: .normal)
        btn.titleLabel?.font = UIFont.systemFont(ofSize: 13.5, weight: .semibold)
        btn.backgroundColor = ShowLogTheme.color(hex: color)
        btn.layer.cornerRadius = 8
        btn.heightAnchor.constraint(equalToConstant: 42).isActive = true
        btn.addTarget(self, action: action, for: .touchUpInside)
        return btn
    }

    // MARK: - Actions

    @objc private func openHubDefault() { ShowLog.show(from: self) }
    @objc private func openNetworkTab() { ShowLog.showNetworkLogs(from: self) }
    @objc private func openDeviceTab() { ShowLog.showAppDeviceInfo(from: self) }
    @objc private func openCustomTab() { ShowLog.showCustomPanel(from: self) }
    @objc private func openFileBrowserTab() { ShowLog.showFileBrowser(from: self) }

    @objc private func simulateSuccessRequest() {
        let record = HttpLogRecord.Builder()
            .url("https://api.example.com/v1/user/login?client=ios_sdk")
            .host("api.example.com")
            .path("/v1/user/login")
            .method("POST")
            .statusCode(200)
            .success(true)
            .message("登录成功")
            .requestHeaders("Content-Type: application/json\nAuthorization: ****** [REDACTED]")
            .requestBody("{\n  \"username\": \"developer\",\n  \"device\": \"iPhone16,2\"\n}")
            .responseHeaders("Content-Type: application/json; charset=utf-8\nX-Trace-Id: req-99881")
            .responseBody("{\n  \"code\": 0,\n  \"message\": \"登录成功\",\n  \"data\": {\n    \"uid\": 102400,\n    \"nickname\": \"ShowLog体验官\"\n  }\n}")
            .contentType("application/json")
            .requestSize(62)
            .responseSize(128)
            .durationMs(86)
            .build()
        ShowLog.report(record: record)
        statusLabel.text = "✅ 已上报 1 条业务成功请求 (/v1/user/login)"
    }

    @objc private func simulateBusinessFailRequest() {
        let record = HttpLogRecord.Builder()
            .url("https://api.example.com/v1/order/checkout")
            .host("api.example.com")
            .path("/v1/order/checkout")
            .method("POST")
            .statusCode(200)
            .success(false)
            .message("账户可用余额不足 (code=4001)")
            .requestHeaders("Content-Type: application/json\nAuthorization: ****** [REDACTED]")
            .requestBody("{\n  \"skuId\": \"SKU_PRO_2026\",\n  \"amount\": 99900\n}")
            .responseHeaders("Content-Type: application/json")
            .responseBody("{\n  \"code\": 4001,\n  \"message\": \"账户可用余额不足\",\n  \"data\": null\n}")
            .contentType("application/json")
            .requestSize(54)
            .responseSize(76)
            .durationMs(142)
            .errorMessage("HTTP 状态码为 200，但业务裁决器判定 code=4001 为业务失败")
            .build()
        ShowLog.report(record: record)
        statusLabel.text = "❌ 已上报 1 条 HTTP 200 业务失败请求 (/v1/order/checkout)"
    }

    @objc private func simulateBatchGroupRequests() {
        for i in 1...5 {
            let ok = (i != 4)
            let record = HttpLogRecord.Builder()
                .url("https://api.example.com/v1/feed/recommend?page=\(i)")
                .host("api.example.com")
                .path("/v1/feed/recommend")
                .method("GET")
                .statusCode(ok ? 200 : 502)
                .success(ok)
                .message(ok ? "OK" : "Bad Gateway")
                .durationMs(Int64(35 + i * 18))
                .responseBody("{\n  \"code\": \(ok ? 0 : 502),\n  \"page\": \(i)\n}")
                .build()
            ShowLog.report(record: record)
        }
        statusLabel.text = "📦 已批量写入 5 条 /v1/feed/recommend 请求，可在控制台切换「分组」模式体验折叠！"
    }

    @objc private func simulateManualPayloadReport() {
        let payload = DemoCustomSocketPayload()
        ShowLog.report(payload: payload)
        statusLabel.text = "📝 已通过强契约 HttpLogPayload 上报 1 条自定义网关报文！"
    }

    @objc private func triggerRealURLSessionRequest() {
        guard let url = URL(string: "https://httpbin.org/get?sdk=ShowLog_iOS_v6") else { return }
        var req = URLRequest(url: url)
        req.setValue("Bearer demo_secret_token_value", forHTTPHeaderField: "Authorization")
        statusLabel.text = "🌐 正在通过 URLSession 请求 httpbin.org（ShowLogURLProtocol 自动拦截中）..."
        URLSession.shared.dataTask(with: req) { [weak self] _, response, error in
            DispatchQueue.main.async {
                if let err = error {
                    self?.statusLabel.text = "⚠️ URLSession 请求结束（含网络错误，已自动记录到 ShowLog）: \(err.localizedDescription)"
                } else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? 200
                    self?.statusLabel.text = "✅ URLSession 真实请求完成 (HTTP \(code))，已被 ShowLogURLProtocol 自动拦截入库！"
                }
            }
        }.resume()
    }

    @objc private func toggleSDKEnabled() {
        let nextState = !ShowLog.isEnabled()
        ShowLog.setEnabled(nextState)
        statusLabel.text = nextState
            ? "🟢 ShowLog 已重新启用（悬浮球已挂载，拦截器恢复工作）"
            : "⚪ ShowLog 已关闭（零开销直通模式，悬浮球已卸载）"
    }
}

/// 强契约 `HttpLogPayload` 实现示例（11 个方法编译器强制检查）。
private final class DemoCustomSocketPayload: NSObject, HttpLogPayload {
    func getUrl() -> String { "https://gateway.example.com/rpc/wallet.queryBalance" }
    func getMethod() -> String { "POST" }
    func getHttpCode() -> Int { 200 }
    func getMessage() -> String { "RPC 调用成功" }
    func isSuccess() -> Bool { true }
    func getDurationMs() -> Int64 { 53 }
    func getRequestHeaders() -> [String: String]? {
        ["X-RPC-Version": "2.0", "token": "sensitive_user_token_value"]
    }
    func getResponseHeaders() -> [String: String]? {
        ["Content-Type": "application/json"]
    }
    func getRequestBody() -> Any? {
        ["uid": 88888, "currency": "CNY"]
    }
    func getResponseBody() -> Any? {
        ["code": 0, "balance": "12800.50", "currency": "CNY"]
    }
    func getError() -> Error? { nil }
}

/// 自定义扩展面板构建示例。
enum DemoCustomPanelBuilder {
    static func populate(into parent: UIView, dialogController: UIViewController) {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(stack)

        let title = UILabel()
        title.text = "🛠️ 宿主业务环境切换与 Mock 控制台"
        title.font = UIFont.systemFont(ofSize: 15, weight: .bold)
        title.textColor = ShowLogTheme.textPrimary

        let desc = UILabel()
        desc.text = "当前环境：Staging 预发环境 (https://api-staging.example.com)\n点击下方按钮可切换宿主网关并主动关闭 ShowLog 调试弹窗："
        desc.font = UIFont.systemFont(ofSize: 12.5)
        desc.textColor = ShowLogTheme.textSecondary
        desc.numberOfLines = 0

        let switchBtn = UIButton(type: .system)
        switchBtn.setTitle("⚡ 切换至生产环境并关闭调试弹窗", for: .normal)
        switchBtn.setTitleColor(.white, for: .normal)
        switchBtn.titleLabel?.font = UIFont.systemFont(ofSize: 13.5, weight: .bold)
        switchBtn.backgroundColor = ShowLogTheme.bgPillSelected
        switchBtn.layer.cornerRadius = 8
        switchBtn.heightAnchor.constraint(equalToConstant: 40).isActive = true
        let action = UIAction { _ in
            dialogController.dismiss(animated: true)
        }
        if #available(iOS 14.0, *) {
            switchBtn.addAction(action, for: .touchUpInside)
        }

        stack.addArrangedSubview(title)
        stack.addArrangedSubview(desc)
        stack.addArrangedSubview(switchBtn)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: parent.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -16)
        ])
    }
}

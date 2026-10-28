import UIKit
import ShowLog

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // 准备沙盒演示文件目录，供「文件浏览」Tab 直接预览演示
        let sandboxDemoDir = prepareDemoSandboxFiles()

        // 1. 初始化 ShowLog（配置数据库上限、敏感头脱敏与沙盒文件浏览根目录）
        let config = ShowLogConfig.Builder()
            .maxDatabaseLogLimit(10000)
            .maxBodyBytes(256 * 1024)
            .addRedactHeader("X-Custom-Token")
            .enabled(true)
            .showFloatingView(true)
            .fileBrowserRootPath(sandboxDemoDir)
            .fileBrowserTabTitle("沙盒文件")
            .build()
        ShowLog.initialize(config: config)

        // 2. 配置全局业务成功裁决器（演示 HTTP 200 但业务 JSON code != 0 时自动判定为业务失败）
        ShowLog.setBusinessJudgerBlock { context in
            if let error = context.getError() {
                return HttpLogJudgementResult.failure("网络传输失败: \(error.localizedDescription)")
            }
            guard (200..<300).contains(context.getHttpCode()) else {
                return HttpLogJudgementResult.failure("HTTP 状态码异常: \(context.getHttpCode())")
            }
            if let json = context.optResponseBodyAsJson(),
               let bizCode = json["code"] as? Int {
                let msg = (json["message"] as? String) ?? (json["msg"] as? String)
                if bizCode == 0 || bizCode == 200 {
                    return HttpLogJudgementResult.success(msg ?? "业务成功")
                } else {
                    return HttpLogJudgementResult.failure(msg ?? "业务错误(code=\(bizCode))")
                }
            }
            return HttpLogJudgementResult.success("OK")
        }

        // 3. 注册业务自定义扩展面板（演示环境切换、Mock 开关与主动关闭调试弹窗）
        ShowLog.registerCustomPanel(title: "环境与Mock") { parent, dialogController in
            DemoCustomPanelBuilder.populate(into: parent, dialogController: dialogController)
        }

        return true
    }

    // MARK: - UISceneSession Lifecycle

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    private func prepareDemoSandboxFiles() -> String {
        let docs = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first
            ?? NSTemporaryDirectory()
        let demoRoot = (docs as NSString).appendingPathComponent("ShowLogDemoSandbox")
        let logsSubDir = (demoRoot as NSString).appendingPathComponent("runtime_logs")
        try? FileManager.default.createDirectory(atPath: logsSubDir, withIntermediateDirectories: true)

        let logFile = (logsSubDir as NSString).appendingPathComponent("app_startup_2026-10-28.log")
        let sampleLog = """
        [2026-10-28 12:00:01.015] [INFO] [ShowLogExample] Application didFinishLaunchingWithOptions
        [2026-10-28 12:00:01.028] [INFO] [ShowLog] SQLite WAL storage initialized at Application Support/ShowLog/showlog_traffic.db
        [2026-10-28 12:00:01.045] [DEBUG] [Network] URLProtocol interceptor attached to URLSessionConfiguration.default
        [2026-10-28 12:00:02.120] [WARN] [Auth] Token will expire in 300 seconds, scheduled silent refresh.
        """
        try? sampleLog.data(using: .utf8)?.write(to: URL(fileURLWithPath: logFile))

        let configJsonFile = (demoRoot as NSString).appendingPathComponent("feature_flags.json")
        let sampleJson = """
        {
          "env": "staging",
          "enableNewCheckout": true,
          "maxRetryCount": 3,
          "gatewayHost": "https://api-staging.example.com"
        }
        """
        try? sampleJson.data(using: .utf8)?.write(to: URL(fileURLWithPath: configJsonFile))
        return demoRoot
    }
}

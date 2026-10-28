import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// ShowLog 唯一顶层门面类（1:1 复刻 Android `ShowLog.java`）。
/// 为什么这样做：
/// 1. 采用门面模式（Facade），将内部双层仓储、SQLite WAL 数据库、URLProtocol 自动拦截器、业务裁决器、自定义扩展面板以及免权限悬浮球生命周期全部封装在极简静态 API 之后；
/// 2. 全面支持 `@objcMembers`，Swift 与 Objective-C 宿主均可零成本调用；
/// 3. 当 `enabled = false`（生产环境关闭）时，拦截器、上报接口与 UI 弹窗 100% 静默直通，零内存与 CPU 开销。
@objcMembers
public final class ShowLog: NSObject {

    private static let stateLock = NSRecursiveLock()
    private static var currentConfig: ShowLogConfig = ShowLogConfig.defaultConfig()
    private static var enabledFlag: Bool = true
    private static var businessJudger: HttpLogBusinessJudger?

    private override init() {
        super.init()
    }

    // MARK: - Enable / Disable State

    /// 判断当前是否启用了日志调试监控（生产环境关闭时返回 false）。
    public static func isEnabled() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return enabledFlag
    }

    /// 动态设置是否启用日志调试监控。
    /// 当传入 `false` 时，URLProtocol 拦截器 100% 直通放行，悬浮球自动隐去并关闭已打开的调试弹框。
    public static func setEnabled(_ enabled: Bool) {
        stateLock.lock()
        enabledFlag = enabled
        let cfg = currentConfig
        stateLock.unlock()

        #if canImport(UIKit)
        DispatchQueue.main.async {
            if !enabled {
                ShowLogFloatWindow.shared.detachAndHide()
            } else if cfg.showFloatingView {
                ShowLogFloatWindow.shared.attachAndShow()
            }
        }
        #endif
    }

    // MARK: - Initialization

    /// Objective-C 极简默认初始化入口（`[ShowLog initSDK]`）。
    @objc(initSDK)
    public static func initSDK() {
        initialize(config: ShowLogConfig.defaultConfig())
    }

    /// 初始化 ShowLog SDK（不传参数时使用默认配置：保留最新 10000 条日志，默认开启免权限悬浮球与 URLSession 自动拦截）。
    /// 支持 `ShowLog.initialize()` 与 `ShowLog.initialize(config: customConfig)` 两种调用方式。
    public static func initialize(config: ShowLogConfig = ShowLogConfig.defaultConfig()) {
        stateLock.lock()
        currentConfig = config
        enabledFlag = config.enabled
        stateLock.unlock()

        // 1. 初始化双层高性能仓储与 SQLite 数据库
        HttpLogRepository.shared.configure(with: config)

        // 2. 注册 URLProtocol 自动拦截与可选 URLSessionConfiguration 注入
        URLSessionConfigurationInjector.enableAutomaticInterception(
            swizzleConfiguration: config.enableURLSessionSwizzling
        )

        // 3. 挂载或卸载全局免权限悬浮球
        #if canImport(UIKit)
        DispatchQueue.main.async {
            if config.enabled && config.showFloatingView {
                ShowLogFloatWindow.shared.attachAndShow()
            } else {
                ShowLogFloatWindow.shared.detachAndHide()
            }
        }
        #endif
    }

    /// 获取当前生效的全局配置。
    public static func getConfig() -> ShowLogConfig {
        stateLock.lock()
        defer { stateLock.unlock() }
        return currentConfig
    }

    // MARK: - URLProtocol & URLSessionConfiguration Injection

    /// 获取 URLProtocol 拦截类（供自定义 `URLSessionConfiguration.protocolClasses` 手动注册）。
    public static func protocolClass() -> AnyClass {
        return ShowLogURLProtocol.self
    }

    /// 便捷将 `ShowLogURLProtocol` 注入到指定 `URLSessionConfiguration`（内部防重，不会重复添加）。
    public static func inject(into configuration: URLSessionConfiguration) {
        URLSessionConfigurationInjector.inject(into: configuration)
    }

    // MARK: - Business Judger

    /// 设置全局业务成功裁决拦截器（协议对象形式）。
    public static func setBusinessJudger(_ judger: HttpLogBusinessJudger?) {
        stateLock.lock()
        businessJudger = judger
        stateLock.unlock()
    }

    /// 设置全局业务成功裁决拦截器（闭包形式，方便 Swift / ObjC Block 快速接入）。
    public static func setBusinessJudgerBlock(_ block: ((HttpLogRequestContext) -> HttpLogJudgementResult)?) {
        stateLock.lock()
        if let block = block {
            businessJudger = ClosureBusinessJudger(block: block)
        } else {
            businessJudger = nil
        }
        stateLock.unlock()
    }

    /// 获取当前配置的业务成功裁决拦截器。
    public static func getBusinessJudger() -> HttpLogBusinessJudger? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return businessJudger
    }

    // MARK: - Manual Reporting

    /// 强契约非 URLSession / 自定义网络库日志上报入口。
    public static func report(payload: HttpLogPayload) {
        guard isEnabled() else { return }
        let record = HttpLogRecord.fromPayload(payload)
        report(record: record)
    }

    /// 强契约日志上报别名。
    public static func record(payload: HttpLogPayload) {
        report(payload: payload)
    }

    /// 实体对象直接上报入口。
    public static func report(record: HttpLogRecord) {
        guard isEnabled() else { return }
        HttpLogRepository.shared.enqueueLog(record)
    }

    /// 实体对象直接上报别名。
    public static func record(_ record: HttpLogRecord) {
        report(record: record)
    }

    /// 清空所有网络日志记录。
    public static func clearAllLogs() {
        HttpLogRepository.shared.clearAll()
    }

    /// 彻底销毁并释放 ShowLog。
    public static func destroy() {
        setEnabled(false)
        HttpLogRepository.shared.shutdown()
    }

    // MARK: - Custom Extension Panel

    /// 注册业务自定义扩展面板（协议实现形式）。
    public static func registerCustomPanel(title: String?, provider: CustomPanelProvider) {
        CustomPanelManager.shared.registerCustomPanel(title: title, provider: provider)
    }

    /// 注册业务自定义扩展面板（闭包形式）。
    public static func registerCustomPanel(
        title: String?,
        onCreateView: @escaping (_ parent: UIView, _ dialogController: UIViewController) -> Void,
        onDestroyView: (() -> Void)? = nil
    ) {
        let adapter = ClosureCustomPanelProvider(onCreateView: onCreateView, onDestroyView: onDestroyView)
        CustomPanelManager.shared.registerCustomPanel(title: title, provider: adapter)
    }

    // MARK: - Show Hub Dialog Entrypoints

    /// 编程式呼出全景调试中枢（等价于 `show()`）。
    public static func openHub() {
        show()
    }

    /// 编程式收起当前全景调试中枢。
    public static func closeHub() {
        #if canImport(UIKit)
        DispatchQueue.main.async {
            if let root = ShowLogFloatWindow.shared.rootViewController,
               let presented = root.presentedViewController as? ShowLogHubViewController {
                presented.dismiss(animated: true, completion: nil)
            }
        }
        #endif
    }

    /// 查询当前是否正在展示 Hub 界面。
    public static var isHubPresented: Bool {
        #if canImport(UIKit)
        guard let root = ShowLogFloatWindow.shared.rootViewController else { return false }
        return root.presentedViewController is ShowLogHubViewController
        #else
        return false
        #endif
    }

    /// 设置悬浮球可见性。
    public static func setFloatWindowVisible(_ visible: Bool) {
        #if canImport(UIKit)
        DispatchQueue.main.async {
            if visible {
                ShowLogFloatWindow.shared.attachAndShow()
            } else {
                ShowLogFloatWindow.shared.detachAndHide()
            }
        }
        #endif
    }

    /// 查询悬浮球当前是否可见。
    public static var isFloatWindowVisible: Bool {
        #if canImport(UIKit)
        return !ShowLogFloatWindow.shared.isHidden && ShowLogFloatWindow.shared.alpha > 0.01
        #else
        return false
        #endif
    }

    /// 呼出全景调试中枢（默认定位至上次浏览的 Tab 或网络日志）。
    public static func show(from presenter: UIViewController? = nil) {
        show(initialTab: ShowLogHubViewController.lastSelectedTab, from: presenter)
    }

    /// 呼出全景调试中枢并定位到指定 Tab（`TAB_NETWORK` / `TAB_DEVICE` / `TAB_CUSTOM` / `TAB_FILE_BROWSER`）。
    public static func show(initialTab: Int, from presenter: UIViewController? = nil) {
        guard isEnabled() else { return }
        let cfg = getConfig()
        #if canImport(UIKit)
        DispatchQueue.main.async {
            guard isEnabled() else { return }
            let targetPresenter = presenter ?? resolveDefaultPresenter()
            guard let hostVC = targetPresenter else { return }
            // 若当前已弹出 ShowLogHubViewController，则直接切换其选中 Tab，避免重复叠层弹窗
            if let existingHub = hostVC as? ShowLogHubViewController {
                existingHub.selectTab(initialTab, animated: true)
                return
            }
            if let presentedHub = hostVC.presentedViewController as? ShowLogHubViewController {
                presentedHub.selectTab(initialTab, animated: true)
                return
            }
            let hubVC = ShowLogHubViewController(initialTab: initialTab, config: cfg)
            hostVC.present(hubVC, animated: true)
        }
        #else
        _ = ShowLogHubViewController(initialTab: initialTab, config: cfg)
        #endif
    }

    /// 呼出网络日志调试面板（兼容入口，定位至 `TAB_NETWORK`）。
    public static func showConsole(from presenter: UIViewController? = nil) {
        show(initialTab: ShowLogHubViewController.TAB_NETWORK, from: presenter)
    }

    /// 呼出网络日志调试面板（定位至 `TAB_NETWORK`）。
    public static func showNetworkLogs(from presenter: UIViewController? = nil) {
        show(initialTab: ShowLogHubViewController.TAB_NETWORK, from: presenter)
    }

    /// 呼出设备与应用全景信息看板（定位至 `TAB_DEVICE`）。
    public static func showAppDeviceInfo(from presenter: UIViewController? = nil) {
        show(initialTab: ShowLogHubViewController.TAB_DEVICE, from: presenter)
    }

    /// 呼出自定义扩展面板（定位至 `TAB_CUSTOM`）。
    public static func showCustomPanel(from presenter: UIViewController? = nil) {
        show(initialTab: ShowLogHubViewController.TAB_CUSTOM, from: presenter)
    }

    /// 呼出沙盒文件浏览面板（定位至 `TAB_FILE_BROWSER`；未配置根目录时自动回退至 `TAB_NETWORK`）。
    public static func showFileBrowser(from presenter: UIViewController? = nil) {
        show(initialTab: ShowLogHubViewController.TAB_FILE_BROWSER, from: presenter)
    }

    #if canImport(UIKit)
    private static func resolveDefaultPresenter() -> UIViewController? {
        if !ShowLogFloatWindow.shared.isHidden,
           let floatRoot = ShowLogFloatWindow.shared.rootViewController {
            return topMostViewController(from: floatRoot)
        }
        let windows = UIApplication.shared.windows.filter { $0 !== ShowLogFloatWindow.shared && !$0.isHidden }
        if let keyWin = windows.first(where: { $0.isKeyWindow }) ?? windows.first,
           let root = keyWin.rootViewController {
            return topMostViewController(from: root)
        }
        ShowLogFloatWindow.shared.bindActiveWindowSceneIfNeeded()
        ShowLogFloatWindow.shared.isHidden = false
        return ShowLogFloatWindow.shared.rootViewController
    }

    private static func topMostViewController(from root: UIViewController) -> UIViewController {
        if let presented = root.presentedViewController, !presented.isBeingDismissed {
            return topMostViewController(from: presented)
        }
        if let nav = root as? UINavigationController, let visible = nav.visibleViewController {
            return topMostViewController(from: visible)
        }
        if let tab = root as? UITabBarController, let selected = tab.selectedViewController {
            return topMostViewController(from: selected)
        }
        return root
    }
    #endif
}

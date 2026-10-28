import Foundation

/// 自定义扩展面板管理器（对齐 Android `CustomPanelManager.java`）。
/// 为什么这样做：
/// 统一集中管理开发者注入的自定义调试扩展，将标题和提供者作为一个不可变快照发布，避免并发读取时组合出不一致的数据。
@objcMembers
public final class CustomPanelManager: NSObject {

    public static let shared = CustomPanelManager()
    public static let DEFAULT_TAB_TITLE = "自定义扩展"

    /// 一次注册的不可变快照，供界面在同一逻辑操作中一致读取标题与面板实现。
    @objc(CustomPanelRegistration)
    @objcMembers
    public final class Registration: NSObject {
        public let title: String
        public let provider: CustomPanelProvider?

        public init(title: String, provider: CustomPanelProvider?) {
            self.title = title
            self.provider = provider
            super.init()
        }
    }

    private let lock = NSLock()
    private var currentRegistration = Registration(title: CustomPanelManager.DEFAULT_TAB_TITLE, provider: nil)

    private override init() {
        super.init()
    }

    /// 注册自定义面板（标题与提供者原子替换）。
    public func registerCustomPanel(title: String?, provider: CustomPanelProvider) {
        lock.lock()
        defer { lock.unlock() }
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedTitle = !trimmed.isEmpty ? trimmed : currentRegistration.title
        currentRegistration = Registration(title: resolvedTitle, provider: provider)
    }

    /// 注销自定义面板（仅解除注册关系，已打开弹框的销毁回调由弹框关闭时统一触发）。
    public func unregisterCustomPanel() {
        lock.lock()
        defer { lock.unlock() }
        currentRegistration = Registration(title: Self.DEFAULT_TAB_TITLE, provider: nil)
    }

    public func getRegistration() -> Registration {
        lock.lock()
        defer { lock.unlock() }
        return currentRegistration
    }

    public func hasCustomPanel() -> Bool {
        return getRegistration().provider != nil
    }
}

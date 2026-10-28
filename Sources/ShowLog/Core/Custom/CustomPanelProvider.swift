import Foundation
#if canImport(UIKit)
import UIKit
#else
/// macOS 命令行测试环境轻量占位类型（iOS 环境下直接使用系统 UIKit.UIView / UIViewController）。
@objcMembers public class UIView: NSObject {}
@objcMembers public class UIViewController: NSObject {
    public func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        completion?()
    }
}
#endif

/// 自定义扩展面板提供者协议（对齐 Android `CustomPanelProvider.java`）。
/// 为什么这样做：
/// SDK 只负责提供承载父视图 `parent` 与当前调试弹框控制器 `dialogController`，
/// 面板内部 UI、数据加载与交互逻辑完全交还业务方；业务方可在任意业务时机主动调用 `dialogController.dismiss(animated: true)` 关闭调试弹框。
@objc
public protocol CustomPanelProvider: NSObjectProtocol {

    /// 在 SDK 提供的承载父视图中填充业务自定义 UI。
    /// - Parameters:
    ///   - parent: SDK 提供的承载父容器视图，业务方应将自定义子视图添加到该容器中
    ///   - dialogController: 当前 ShowLog 调试中枢视图控制器，可调用 `dismiss(animated:completion:)` 关闭弹框
    func onCreateView(parent: UIView, dialogController: UIViewController)

    /// 面板销毁或调试弹框关闭时的清理回调（可选实现）。
    @objc optional func onDestroyView()
}

/// 闭包形式的 `CustomPanelProvider` 适配器。
@objcMembers
internal final class ClosureCustomPanelProvider: NSObject, CustomPanelProvider {
    private let createHandler: (UIView, UIViewController) -> Void
    private let destroyHandler: (() -> Void)?

    init(
        onCreateView: @escaping (UIView, UIViewController) -> Void,
        onDestroyView: (() -> Void)?
    ) {
        self.createHandler = onCreateView
        self.destroyHandler = onDestroyView
        super.init()
    }

    func onCreateView(parent: UIView, dialogController: UIViewController) {
        createHandler(parent, dialogController)
    }

    func onDestroyView() {
        destroyHandler?()
    }
}

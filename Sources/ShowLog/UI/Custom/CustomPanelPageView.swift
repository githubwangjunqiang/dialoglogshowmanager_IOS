import Foundation
#if canImport(UIKit)
import UIKit

/// 自定义扩展面板承载视图（1:1 对齐 Android `CustomPanelPageView.java`）。
/// 为什么这样做：
/// 1. 同一弹框实例生命周期内切换 Tab 仅回调一次 `onCreateView`，保持业务面板内部输入框、开关状态不丢失；
/// 2. 弹框关闭时统一调用 `teardown()` -> `onDestroyView()`；
/// 3. 未注册自定义扩展时展示内置暗黑接入指南与代码示例。
@objcMembers
public final class CustomPanelPageView: UIView {

    public weak var hostDialogController: UIViewController?
    private var registration: CustomPanelManager.Registration?
    private var boundProvider: CustomPanelProvider?
    private var isBinding = false
    private var teardownPending = false

    private let contentContainer = UIView()
    private let emptyGuideScroll = UIScrollView()

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    public func setRegistration(_ registration: CustomPanelManager.Registration) {
        self.registration = registration
    }

    private func setupUI() {
        backgroundColor = .clear

        contentContainer.backgroundColor = .clear
        contentContainer.isHidden = true
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentContainer)

        emptyGuideScroll.backgroundColor = .clear
        emptyGuideScroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(emptyGuideScroll)

        let guideStack = UIStackView()
        guideStack.axis = .vertical
        guideStack.spacing = 10
        guideStack.translatesAutoresizingMaskIntoConstraints = false
        emptyGuideScroll.addSubview(guideStack)

        let titleLabel = UILabel()
        titleLabel.text = "🧩 尚未注册业务自定义扩展面板"
        titleLabel.font = UIFont.systemFont(ofSize: 15, weight: .bold)
        titleLabel.textColor = ShowLogTheme.textPrimary

        let descLabel = UILabel()
        descLabel.text = "你可以通过 ShowLog.registerCustomPanel 注入环境切换（测试/预发/生产）、Mock 开关、快捷登录或实验特性面板。SDK 提供承载父容器与弹框控制器，允许业务随时调用 dialogController.dismiss(animated: true) 关闭弹框。"
        descLabel.font = UIFont.systemFont(ofSize: 12.5, weight: .regular)
        descLabel.textColor = ShowLogTheme.textSecondary
        descLabel.numberOfLines = 0

        let codeBox = UILabel()
        codeBox.font = ShowLogTheme.monospacedFont(size: 11.5)
        codeBox.textColor = ShowLogTheme.actionBtn
        codeBox.backgroundColor = ShowLogTheme.bgPrimary
        codeBox.layer.cornerRadius = 8
        codeBox.layer.borderWidth = 1
        codeBox.layer.borderColor = ShowLogTheme.bgCardStroke.cgColor
        codeBox.clipsToBounds = true
        codeBox.numberOfLines = 0
        codeBox.text = """
          // Swift 极简闭包注册示例：
          ShowLog.registerCustomPanel(title: "环境切换") { parent, dialogVC in
              let btn = UIButton(type: .system)
              btn.setTitle("切换至预发环境并关闭弹窗", for: .normal)
              parent.addSubview(btn)
              // 切换成功后可随时关闭调试中枢：
              // dialogVC.dismiss(animated: true)
          }
        """

        guideStack.addArrangedSubview(titleLabel)
        guideStack.addArrangedSubview(descLabel)
        guideStack.addArrangedSubview(codeBox)

        NSLayoutConstraint.activate([
            contentContainer.topAnchor.constraint(equalTo: topAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
            contentContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: trailingAnchor),

            emptyGuideScroll.topAnchor.constraint(equalTo: topAnchor),
            emptyGuideScroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            emptyGuideScroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            emptyGuideScroll.trailingAnchor.constraint(equalTo: trailingAnchor),

            guideStack.topAnchor.constraint(equalTo: emptyGuideScroll.topAnchor, constant: 16),
            guideStack.bottomAnchor.constraint(equalTo: emptyGuideScroll.bottomAnchor, constant: -16),
            guideStack.leadingAnchor.constraint(equalTo: emptyGuideScroll.leadingAnchor, constant: 16),
            guideStack.trailingAnchor.constraint(equalTo: emptyGuideScroll.trailingAnchor, constant: -16),
            guideStack.widthAnchor.constraint(equalTo: emptyGuideScroll.widthAnchor, constant: -32)
        ])
    }

    public func renderCustomContent() {
        guard let provider = registration?.provider else {
            releaseBoundPanel()
            showEmptyGuide()
            return
        }

        // 同一弹框生命周期内已绑定同一 provider 时直接复用，不重复回调 onCreateView
        if boundProvider === provider {
            return
        }

        guard let hostVC = hostDialogController else {
            releaseBoundPanel()
            showEmptyGuide()
            return
        }

        releaseBoundPanel()
        boundProvider = provider
        contentContainer.isHidden = false
        emptyGuideScroll.isHidden = true

        isBinding = true
        if let customView = provider.createPanelView?() {
            customView.translatesAutoresizingMaskIntoConstraints = false
            contentContainer.addSubview(customView)
            NSLayoutConstraint.activate([
                customView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
                customView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
                customView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
                customView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor)
            ])
        } else {
            provider.onCreateView?(parent: contentContainer, dialogController: hostVC)
        }
        isBinding = false

        if teardownPending {
            teardownPending = false
            teardown()
        }
    }

    public func teardown() {
        if isBinding {
            teardownPending = true
            return
        }
        releaseBoundPanel()
        showEmptyGuide()
    }

    private func releaseBoundPanel() {
        let provider = boundProvider
        boundProvider = nil
        provider?.onDestroyView?()
        contentContainer.subviews.forEach { $0.removeFromSuperview() }
    }

    private func showEmptyGuide() {
        contentContainer.isHidden = true
        emptyGuideScroll.isHidden = false
    }
}
#endif

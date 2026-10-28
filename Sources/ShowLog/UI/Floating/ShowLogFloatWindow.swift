import Foundation
#if canImport(UIKit)
import UIKit

/// 免权限触摸透传 `UIWindow` + 吸边拖拽悬浮球（对齐 Android `HttpLogFloatView`）。
/// 为什么这样做：
/// 1. 重写 `point(inside:with:)`：当没有弹出调试中枢弹框时，仅悬浮球按钮 `48x48pt` 区域响应触摸，其余屏幕区域 100% 透传给宿主 App；
/// 2. 支持 iOS 13+ 多 `UIWindowScene` 延迟挂载、横竖屏旋转与 SafeArea 坐标自动钳制；
/// 3. 拖拽松手后通过弹簧动画（阻尼 `0.78`）自动吸附至屏幕左侧或右侧边缘。
@objcMembers
public final class ShowLogFloatWindow: UIWindow {

    public static let shared = ShowLogFloatWindow(frame: UIScreen.main.bounds)

    private let floatButton = UIButton(type: .custom)
    private let throttler = ClickThrottler(intervalMs: ShowLogTheme.throttleMs)
    private var isDragging = false
    private let buttonSize: CGFloat = 48.0
    private let edgeMargin: CGFloat = 8.0

    public override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    @available(iOS 13.0, *)
    public override init(windowScene: UIWindowScene) {
        super.init(windowScene: windowScene)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        backgroundColor = .clear
        windowLevel = UIWindow.Level.statusBar - 1
        if #available(iOS 13.0, *) {
            overrideUserInterfaceStyle = .dark
        }

        let hostVC = FloatContainerViewController()
        hostVC.onBoundsTransition = { [weak self] newSize in
            self?.clampFloatButtonToBounds(containerSize: newSize, animated: true)
        }
        rootViewController = hostVC

        setupFloatButton()
        if let rootView = hostVC.view {
            rootView.addSubview(floatButton)
            let initialY = max(120.0, UIScreen.main.bounds.height * 0.62)
            let initialX = UIScreen.main.bounds.width - buttonSize - edgeMargin
            floatButton.frame = CGRect(x: initialX, y: initialY, width: buttonSize, height: buttonSize)
        }

        registerSceneObservers()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupFloatButton() {
        floatButton.backgroundColor = ShowLogTheme.color(hex: 0x1A1A1E, alpha: 0.92)
        floatButton.layer.cornerRadius = buttonSize / 2.0
        floatButton.layer.borderWidth = 1.5
        floatButton.layer.borderColor = ShowLogTheme.textMethod.cgColor
        floatButton.layer.shadowColor = UIColor.black.cgColor
        floatButton.layer.shadowOpacity = 0.45
        floatButton.layer.shadowOffset = CGSize(width: 0, height: 3)
        floatButton.layer.shadowRadius = 6

        let titleAttr = NSAttributedString(
            string: "LOG",
            attributes: [
                .font: UIFont.systemFont(ofSize: 12, weight: .heavy),
                .foregroundColor: ShowLogTheme.textMethod
            ]
        )
        floatButton.setAttributedTitle(titleAttr, for: .normal)
        floatButton.addTarget(self, action: #selector(onFloatButtonTapped), for: .touchUpInside)

        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(onFloatButtonPanned(_:)))
        floatButton.addGestureRecognizer(panGesture)
    }

    private func registerSceneObservers() {
        if #available(iOS 13.0, *) {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(onSceneOrAppActivated),
                name: UIScene.didActivateNotification,
                object: nil
            )
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onSceneOrAppActivated),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @objc private func onSceneOrAppActivated() {
        let cfg = ShowLog.getConfig()
        if ShowLog.isEnabled() && cfg.showFloatingView {
            attachAndShow()
        }
    }

    public func attachAndShow() {
        DispatchQueue.main.async {
            guard ShowLog.isEnabled(), ShowLog.getConfig().showFloatingView else {
                self.detachAndHide()
                return
            }
            self.bindActiveWindowSceneIfNeeded()
            self.frame = UIScreen.main.bounds
            self.isHidden = false
            self.floatButton.isHidden = false
            self.clampFloatButtonToBounds(containerSize: self.bounds.size, animated: false)
        }
    }

    public func detachAndHide() {
        DispatchQueue.main.async {
            if let presented = self.rootViewController?.presentedViewController {
                presented.dismiss(animated: false)
            }
            self.floatButton.isHidden = true
            self.isHidden = true
        }
    }

    public func bindActiveWindowSceneIfNeeded() {
        if #available(iOS 13.0, *) {
            if windowScene != nil && windowScene?.activationState == .foregroundActive {
                return
            }
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            if let activeScene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first {
                self.windowScene = activeScene
            }
        }
    }

    // MARK: - Touch Pass-Through

    public override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard !isHidden, alpha > 0.01 else { return false }
        // 若调试中枢弹框（或子详情弹框）正处于展示状态，接管全屏触摸事件
        if rootViewController?.presentedViewController != nil {
            return true
        }
        guard !floatButton.isHidden, let rootView = rootViewController?.view else {
            return false
        }
        let pointInRoot = convert(point, to: rootView)
        return floatButton.frame.insetBy(dx: -4, dy: -4).contains(pointInRoot)
    }

    // MARK: - Actions & Snap Animation

    @objc private func onFloatButtonTapped() {
        guard !isDragging else { return }
        guard !throttler.isThrottled() else { return }
        if rootViewController?.presentedViewController != nil {
            return
        }
        ShowLog.show()
    }

    @objc private func onFloatButtonPanned(_ gesture: UIPanGestureRecognizer) {
        guard let rootView = rootViewController?.view else { return }
        let translation = gesture.translation(in: rootView)

        switch gesture.state {
        case .began:
            isDragging = true
        case .changed:
            var center = floatButton.center
            center.x += translation.x
            center.y += translation.y
            floatButton.center = center
            gesture.setTranslation(.zero, in: rootView)
        case .ended, .cancelled, .failed:
            clampFloatButtonToBounds(containerSize: rootView.bounds.size, animated: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.isDragging = false
            }
        default:
            break
        }
    }

    private func clampFloatButtonToBounds(containerSize: CGSize, animated: Bool) {
        guard containerSize.width > 0, containerSize.height > 0 else { return }
        let insets = safeAreaInsets
        let minY = insets.top + 12.0
        let maxY = max(minY, containerSize.height - insets.bottom - 60.0)

        var targetFrame = floatButton.frame
        targetFrame.origin.y = min(max(targetFrame.origin.y, minY), maxY)

        if targetFrame.midX < containerSize.width / 2.0 {
            targetFrame.origin.x = max(edgeMargin, insets.left + edgeMargin)
        } else {
            targetFrame.origin.x = containerSize.width - insets.right - buttonSize - edgeMargin
        }

        if animated {
            UIView.animate(
                withDuration: 0.32,
                delay: 0,
                usingSpringWithDamping: 0.78,
                initialSpringVelocity: 0.6,
                options: [.curveEaseOut, .allowUserInteraction]
            ) {
                self.floatButton.frame = targetFrame
            }
        } else {
            floatButton.frame = targetFrame
        }
    }
}

/// 悬浮窗根控制器（负责监听屏幕旋转与尺寸变化）。
private final class FloatContainerViewController: UIViewController {
    var onBoundsTransition: ((CGSize) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { [weak self] _ in
            self?.onBoundsTransition?(size)
        }, completion: nil)
    }
}
#endif

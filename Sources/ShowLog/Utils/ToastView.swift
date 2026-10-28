import Foundation
#if canImport(UIKit)
import UIKit

/// 轻量级底部暗黑胶囊 Toast 提示组件（零第三方依赖，支持悬浮 Window 或顶层 Window 展示）。
@objcMembers
public final class ToastView: NSObject {

    public static func show(_ message: String, in parentView: UIView? = nil, duration: TimeInterval = 2.0) {
        guard !message.isEmpty else { return }
        DispatchQueue.main.async {
            guard let hostView = parentView ?? topHostWindow() else { return }

            let container = UIView()
            container.backgroundColor = UIColor(red: 0.17, green: 0.17, blue: 0.21, alpha: 0.96)
            container.layer.cornerRadius = 18
            container.layer.borderWidth = 1
            container.layer.borderColor = ShowLogTheme.bgCardStroke.cgColor
            container.layer.shadowColor = UIColor.black.cgColor
            container.layer.shadowOpacity = 0.35
            container.layer.shadowOffset = CGSize(width: 0, height: 4)
            container.layer.shadowRadius = 8
            container.alpha = 0
            container.translatesAutoresizingMaskIntoConstraints = false

            let label = UILabel()
            label.text = message
            label.textColor = ShowLogTheme.textPrimary
            label.font = UIFont.systemFont(ofSize: 13, weight: .medium)
            label.numberOfLines = 2
            label.textAlignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false

            container.addSubview(label)
            hostView.addSubview(container)

            NSLayoutConstraint.activate([
                label.topAnchor.constraint(equalTo: container.topAnchor, constant: 9),
                label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -9),
                label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
                label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),

                container.centerXAnchor.constraint(equalTo: hostView.centerXAnchor),
                container.bottomAnchor.constraint(equalTo: hostView.safeAreaLayoutGuide.bottomAnchor, constant: -36),
                container.widthAnchor.constraint(lessThanOrEqualTo: hostView.widthAnchor, multiplier: 0.88)
            ])

            UIView.animate(withDuration: 0.2) {
                container.alpha = 1
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                UIView.animate(withDuration: 0.25, animations: {
                    container.alpha = 0
                }, completion: { _ in
                    container.removeFromSuperview()
                })
            }
        }
    }

    private static func topHostWindow() -> UIWindow? {
        let windows = UIApplication.shared.windows.filter { !$0.isHidden && $0.alpha > 0 }
        return windows.last ?? UIApplication.shared.windows.first
    }
}
#endif

import Foundation
#if canImport(UIKit)
import UIKit

/// `UIActivityViewController` 系统分享封装（兼容 iPhone 与 iPad Popover 防崩溃）。
@objcMembers
public final class ShareHelper: NSObject {

    /// 分享本地文件（如沙盒日志文件、数据库、图片等）。
    public static func shareFile(
        atPath filePath: String,
        from presenter: UIViewController,
        sourceView: UIView? = nil,
        completion: ((Bool) -> Void)? = nil
    ) {
        let fileURL = URL(fileURLWithPath: filePath)
        guard FileManager.default.fileExists(atPath: filePath) else {
            ToastView.show("文件不存在或无法读取", in: presenter.view)
            completion?(false)
            return
        }
        presentActivityController(items: [fileURL], from: presenter, sourceView: sourceView, completion: completion)
    }

    /// 分享纯文本（如请求/响应报文、cURL 命令、Markdown 诊断报告）。
    public static func shareText(
        _ text: String,
        from presenter: UIViewController,
        sourceView: UIView? = nil,
        completion: ((Bool) -> Void)? = nil
    ) {
        guard !text.isEmpty else {
            completion?(false)
            return
        }
        presentActivityController(items: [text], from: presenter, sourceView: sourceView, completion: completion)
    }

    private static func presentActivityController(
        items: [Any],
        from presenter: UIViewController,
        sourceView: UIView?,
        completion: ((Bool) -> Void)?
    ) {
        DispatchQueue.main.async {
            let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
            if #available(iOS 13.0, *) {
                activityVC.overrideUserInterfaceStyle = .dark
            }
            // iPad 强制配置 popoverPresentationController，彻底杜绝 iPad 下弹出崩溃
            if let popover = activityVC.popoverPresentationController {
                let anchor = sourceView ?? presenter.viewIfLoaded ?? presenter.view
                if let anchor = anchor {
                    popover.sourceView = anchor
                    popover.sourceRect = CGRect(x: anchor.bounds.midX, y: anchor.bounds.midY, width: 1, height: 1)
                }
                popover.permittedArrowDirections = .any
            }
            activityVC.completionWithItemsHandler = { _, completed, _, _ in
                completion?(completed)
            }
            presenter.present(activityVC, animated: true)
        }
    }
}
#endif

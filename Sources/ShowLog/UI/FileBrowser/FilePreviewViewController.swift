import Foundation
#if canImport(UIKit)
import UIKit
import ImageIO

/// 沙盒文件内嵌预览弹框控制器（对齐 Android `FileBrowserView.FilePreviewDialog`）。
/// 支持：
/// 1. 文本文件：通过 `PagedTextLoader` 按 `32KB` 分页流式读取（支持上一页 / 下一页），杜绝大日志文件 OOM；
/// 2. 图片文件：使用 `ImageIO` (`CGImageSourceCreateThumbnailAtIndex`) 按视图尺寸降采样解码；
/// 3. 二进制/PDF/数据库等其他文件：展示 `"不支持该文件预览，请点击右上角分享"`；
/// 4. 右上角常驻「分享」按钮（调用 `ShareHelper.shareFile`），且全程强制校验 `isWithinRoot` 防路径穿越。
@objcMembers
public final class FilePreviewViewController: UIViewController {

    public let rootPath: String
    public let filePath: String

    private let dialogCard = UIView()
    private let titleLabel = UILabel()
    private let shareBtn = UIButton(type: .custom)
    private let closeBtn = UIButton(type: .custom)
    private let contentContainer = UIView()

    private let textView = UITextView()
    private let prevPageBtn = UIButton(type: .system)
    private let pageLabel = UILabel()
    private let nextPageBtn = UIButton(type: .system)

    private var pageOffsets: [UInt64] = [0]
    private var currentPageIndex: Int = 0
    private var currentNextOffset: UInt64 = 0
    private var hasMorePages: Bool = false
    private var isLoadingPage: Bool = false
    private let ioQueue = DispatchQueue(label: "com.xq.showlog.filepreview.io", qos: .userInitiated)
    private let throttler = ClickThrottler(intervalMs: ShowLogTheme.throttleMs)

    public init(rootPath: String, filePath: String) {
        self.rootPath = rootPath
        self.filePath = filePath
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
        if #available(iOS 13.0, *) {
            overrideUserInterfaceStyle = .dark
        }
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.68)
        setupUI()
        detectAndLoadPreview()
    }

    private func setupUI() {
        dialogCard.backgroundColor = ShowLogTheme.bgSurface
        dialogCard.layer.cornerRadius = 12
        dialogCard.layer.borderWidth = 1
        dialogCard.layer.borderColor = ShowLogTheme.bgCardStroke.cgColor
        dialogCard.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dialogCard)

        titleLabel.text = (filePath as NSString).lastPathComponent
        titleLabel.font = UIFont.systemFont(ofSize: 14, weight: .bold)
        titleLabel.textColor = ShowLogTheme.textPrimary
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        shareBtn.setTitle("📤 分享", for: .normal)
        shareBtn.setTitleColor(ShowLogTheme.textOnAccent, for: .normal)
        shareBtn.titleLabel?.font = UIFont.systemFont(ofSize: 12, weight: .bold)
        shareBtn.backgroundColor = ShowLogTheme.bgPillSelected
        shareBtn.layer.cornerRadius = 6
        shareBtn.contentEdgeInsets = UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
        shareBtn.translatesAutoresizingMaskIntoConstraints = false
        shareBtn.addTarget(self, action: #selector(handleShare(_:)), for: .touchUpInside)

        closeBtn.setTitle("✕", for: .normal)
        closeBtn.setTitleColor(ShowLogTheme.textPrimary, for: .normal)
        closeBtn.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .bold)
        closeBtn.backgroundColor = ShowLogTheme.statusError
        closeBtn.layer.cornerRadius = 6
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        closeBtn.addTarget(self, action: #selector(handleClose), for: .touchUpInside)

        contentContainer.backgroundColor = ShowLogTheme.bgPrimary
        contentContainer.layer.cornerRadius = 8
        contentContainer.layer.borderWidth = 1
        contentContainer.layer.borderColor = ShowLogTheme.bgCardStroke.cgColor
        contentContainer.clipsToBounds = true
        contentContainer.translatesAutoresizingMaskIntoConstraints = false

        dialogCard.addSubview(titleLabel)
        dialogCard.addSubview(shareBtn)
        dialogCard.addSubview(closeBtn)
        dialogCard.addSubview(contentContainer)

        NSLayoutConstraint.activate([
            dialogCard.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            dialogCard.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            dialogCard.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.90),
            dialogCard.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.78),

            titleLabel.topAnchor.constraint(equalTo: dialogCard.topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: dialogCard.leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: shareBtn.leadingAnchor, constant: -8),

            closeBtn.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            closeBtn.trailingAnchor.constraint(equalTo: dialogCard.trailingAnchor, constant: -12),
            closeBtn.widthAnchor.constraint(equalToConstant: 30),
            closeBtn.heightAnchor.constraint(equalToConstant: 26),

            shareBtn.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            shareBtn.trailingAnchor.constraint(equalTo: closeBtn.leadingAnchor, constant: -8),
            shareBtn.heightAnchor.constraint(equalToConstant: 26),

            contentContainer.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            contentContainer.leadingAnchor.constraint(equalTo: dialogCard.leadingAnchor, constant: 12),
            contentContainer.trailingAnchor.constraint(equalTo: dialogCard.trailingAnchor, constant: -12),
            contentContainer.bottomAnchor.constraint(equalTo: dialogCard.bottomAnchor, constant: -12)
        ])
    }

    private func detectAndLoadPreview() {
        let root = rootPath
        let target = filePath
        ioQueue.async { [weak self] in
            let kind = PagedTextLoader.detectPreviewKind(rootPath: root, filePath: target)
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch kind {
                case .text:
                    self.setupTextPreviewUI()
                    self.loadTextPage(at: 0)
                case .image:
                    self.setupImagePreviewUI()
                case .unsupported:
                    self.showUnsupportedMessage()
                }
            }
        }
    }

    private func setupTextPreviewUI() {
        contentContainer.subviews.forEach { $0.removeFromSuperview() }

        textView.backgroundColor = .clear
        textView.textColor = ShowLogTheme.textPrimary
        textView.font = ShowLogTheme.monospacedFont(size: 12)
        textView.isEditable = false
        textView.isSelectable = true
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 6, bottom: 8, right: 6)
        textView.translatesAutoresizingMaskIntoConstraints = false

        let bottomBar = UIView()
        bottomBar.backgroundColor = ShowLogTheme.bgCard
        bottomBar.translatesAutoresizingMaskIntoConstraints = false

        prevPageBtn.setTitle("⬅ 上一页", for: .normal)
        prevPageBtn.setTitleColor(ShowLogTheme.actionBtn, for: .normal)
        prevPageBtn.setTitleColor(ShowLogTheme.textTertiary, for: .disabled)
        prevPageBtn.titleLabel?.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        prevPageBtn.addTarget(self, action: #selector(handlePrevPage), for: .touchUpInside)
        prevPageBtn.translatesAutoresizingMaskIntoConstraints = false

        pageLabel.font = ShowLogTheme.monospacedFont(size: 12, weight: .medium)
        pageLabel.textColor = ShowLogTheme.textSecondary
        pageLabel.textAlignment = .center
        pageLabel.translatesAutoresizingMaskIntoConstraints = false

        nextPageBtn.setTitle("下一页 ➡", for: .normal)
        nextPageBtn.setTitleColor(ShowLogTheme.actionBtn, for: .normal)
        nextPageBtn.setTitleColor(ShowLogTheme.textTertiary, for: .disabled)
        nextPageBtn.titleLabel?.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        nextPageBtn.addTarget(self, action: #selector(handleNextPage), for: .touchUpInside)
        nextPageBtn.translatesAutoresizingMaskIntoConstraints = false

        bottomBar.addSubview(prevPageBtn)
        bottomBar.addSubview(pageLabel)
        bottomBar.addSubview(nextPageBtn)

        contentContainer.addSubview(textView)
        contentContainer.addSubview(bottomBar)

        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            textView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor),

            bottomBar.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
            bottomBar.heightAnchor.constraint(equalToConstant: 36),

            prevPageBtn.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 12),
            prevPageBtn.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),

            pageLabel.centerXAnchor.constraint(equalTo: bottomBar.centerXAnchor),
            pageLabel.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),

            nextPageBtn.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -12),
            nextPageBtn.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor)
        ])
    }

    private func loadTextPage(at index: Int) {
        guard !isLoadingPage, index >= 0, index < pageOffsets.count else { return }
        isLoadingPage = true
        currentPageIndex = index
        let offset = pageOffsets[index]

        prevPageBtn.isEnabled = false
        nextPageBtn.isEnabled = false
        pageLabel.text = "第 \(index + 1) 页 (32KB/页)"
        textView.text = "正在流式读取文件分块..."

        let root = rootPath
        let target = filePath
        ioQueue.async { [weak self] in
            let pageData = PagedTextLoader.readTextPage(
                rootPath: root,
                filePath: target,
                byteOffset: offset,
                maxBytes: PagedTextLoader.DEFAULT_PAGE_BYTES
            )
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoadingPage = false
                guard let data = pageData else {
                    self.showUnsupportedMessage()
                    return
                }
                self.textView.text = data.text.isEmpty ? "(空文件)" : data.text
                self.textView.setContentOffset(.zero, animated: false)
                self.currentNextOffset = data.nextByteOffset
                self.hasMorePages = data.hasMore
                self.prevPageBtn.isEnabled = (index > 0)
                self.nextPageBtn.isEnabled = data.hasMore
            }
        }
    }

    @objc private func handlePrevPage() {
        guard !throttler.isThrottled(), currentPageIndex > 0 else { return }
        loadTextPage(at: currentPageIndex - 1)
    }

    @objc private func handleNextPage() {
        guard !throttler.isThrottled(), hasMorePages else { return }
        let nextIdx = currentPageIndex + 1
        if nextIdx >= pageOffsets.count {
            pageOffsets.append(currentNextOffset)
        }
        loadTextPage(at: nextIdx)
    }

    private func setupImagePreviewUI() {
        contentContainer.subviews.forEach { $0.removeFromSuperview() }

        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentContainer.topAnchor, constant: 8),
            imageView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor, constant: -8),
            imageView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor, constant: 8),
            imageView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor, constant: -8)
        ])

        let root = rootPath
        let target = filePath
        let maxPixel = Int(max(UIScreen.main.bounds.width, UIScreen.main.bounds.height) * UIScreen.main.scale)

        ioQueue.async { [weak self] in
            guard PagedTextLoader.isWithinRoot(rootPath: root, candidatePath: target) else {
                DispatchQueue.main.async { self?.showUnsupportedMessage() }
                return
            }
            let fileURL = URL(fileURLWithPath: target)
            guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else {
                DispatchQueue.main.async { self?.showUnsupportedMessage() }
                return
            }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(512, maxPixel)
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                DispatchQueue.main.async { self?.showUnsupportedMessage() }
                return
            }
            let uiImage = UIImage(cgImage: cgImage)
            DispatchQueue.main.async {
                imageView.image = uiImage
            }
        }
    }

    private func showUnsupportedMessage() {
        contentContainer.subviews.forEach { $0.removeFromSuperview() }
        let label = UILabel()
        label.text = "不支持该文件预览，请点击右上角分享"
        label.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        label.textColor = ShowLogTheme.textSecondary
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: contentContainer.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: contentContainer.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor, constant: -20)
        ])
    }

    @objc private func handleShare(_ sender: UIButton) {
        guard !throttler.isThrottled() else { return }
        guard PagedTextLoader.isWithinRoot(rootPath: rootPath, candidatePath: filePath) else {
            showUnsupportedMessage()
            return
        }
        ShareHelper.shareFile(atPath: filePath, from: self, sourceView: sender)
    }

    @objc private func handleClose() {
        dismiss(animated: true)
    }
}
#endif

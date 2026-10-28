import Foundation
#if canImport(UIKit)
import UIKit

/// ShowLog 全景调试中枢主弹框控制器（1:1 复刻 Android `ShowLogHubDialog.java`）。
/// 为什么这样做：
/// 1. 弹框尺寸固定为 `screenWidth * 0.96` × `screenHeight * 0.90`；
/// 2. 顶部页签与内容面板由 `ShowLogHubTabPanelBackgroundView` 绘制一体化联合轮廓（二次贝塞尔内凹圆角）；
/// 3. 右上角设置外挂红色关闭挂钩按钮（`#DC2626`），点击热区向外扩展 `12pt`；
/// 4. 3+1 动态可见主 Tab（`🌐 网络日志`、`📱 设备信息`、`🧩 自定义扩展` + 配置了 `fileBrowserRootPath` 时展示 `文件浏览`）；
/// 5. 静态记忆上次浏览的 Tab 索引，且越界时自动纠正回 `TAB_NETWORK (0)`。
@objcMembers
public final class ShowLogHubViewController: UIViewController, UIScrollViewDelegate {

    public static let TAB_NETWORK: Int = 0
    public static let TAB_DEVICE: Int = 1
    public static let TAB_CUSTOM: Int = 2
    public static let TAB_FILE_BROWSER: Int = 3

    private static let baseTabCount = 3
    public private(set) static var lastSelectedTab: Int = TAB_NETWORK

    public let config: ShowLogConfig
    public let tabCount: Int
    public private(set) var currentTab: Int

    private let customRegistration: CustomPanelManager.Registration
    private let throttler = ClickThrottler(intervalMs: ShowLogTheme.throttleMs)

    private let hubContainer = UIView()
    private let tabPanelBackground = ShowLogHubTabPanelBackgroundView()
    private let tabScrollView = UIScrollView()
    private let tabStackView = UIStackView()
    private let closeHookButton = ExpandedTouchButton(type: .custom)
    private let pagesContainer = UIView()

    private var tabButtons: [UIButton] = []
    private var pageViews: [UIView] = []

    private var networkView: HttpLogConsoleView?
    private var deviceView: AppDeviceInfoView?
    private var customView: CustomPanelPageView?
    private var fileBrowserView: FileBrowserView?

    public convenience init(config: ShowLogConfig = ShowLog.getConfig()) {
        self.init(initialTab: Self.lastSelectedTab, config: config)
    }

    public init(initialTab: Int, config: ShowLogConfig = ShowLog.getConfig()) {
        self.config = config
        self.tabCount = (config.fileBrowserRootPath == nil) ? Self.baseTabCount : (Self.baseTabCount + 1)
        let resolvedTab = (initialTab >= Self.TAB_NETWORK && initialTab < self.tabCount) ? initialTab : Self.TAB_NETWORK
        self.currentTab = resolvedTab
        Self.lastSelectedTab = resolvedTab
        self.customRegistration = CustomPanelManager.shared.getRegistration()
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
        view.backgroundColor = UIColor.black.withAlphaComponent(0.65)
        setupHubLayout()
        setupPages()
        selectTab(currentTab, animated: false)
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateSelectedTabOutline()
    }

    public override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        releaseSubPanels()
        super.dismiss(animated: flag, completion: completion)
    }

    private func releaseSubPanels() {
        deviceView?.setDeviceTabActive(false)
        customView?.teardown()
        fileBrowserView?.teardown()
    }

    private func setupHubLayout() {
        hubContainer.backgroundColor = .clear
        hubContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hubContainer)

        tabPanelBackground.translatesAutoresizingMaskIntoConstraints = false
        hubContainer.addSubview(tabPanelBackground)

        // 右上角外挂红色关闭按钮
        closeHookButton.setTitle("×", for: .normal)
        closeHookButton.setTitleColor(.white, for: .normal)
        closeHookButton.titleLabel?.font = UIFont.systemFont(ofSize: 20, weight: .bold)
        closeHookButton.backgroundColor = ShowLogTheme.statusError
        closeHookButton.layer.cornerRadius = 8
        closeHookButton.touchAreaPadding = 12.0
        closeHookButton.translatesAutoresizingMaskIntoConstraints = false
        closeHookButton.addTarget(self, action: #selector(handleCloseHub), for: .touchUpInside)
        hubContainer.addSubview(closeHookButton)

        // 顶部可横向滚动的页签栏（高度 36pt，与 tabPanelBackground.panelTop 对齐）
        tabScrollView.showsHorizontalScrollIndicator = false
        tabScrollView.delegate = self
        tabScrollView.translatesAutoresizingMaskIntoConstraints = false
        hubContainer.addSubview(tabScrollView)

        tabStackView.axis = .horizontal
        tabStackView.spacing = 2
        tabStackView.alignment = .fill
        tabStackView.translatesAutoresizingMaskIntoConstraints = false
        tabScrollView.addSubview(tabStackView)

        let customRawTitle = customRegistration.title
        let customTabTitle = customRawTitle.hasPrefix("🧩") ? customRawTitle : "🧩 \(customRawTitle)"
        var titles = [
            "🌐 网络日志",
            "📱 设备信息",
            customTabTitle
        ]
        if tabCount > Self.baseTabCount {
            let fileTitle = config.fileBrowserTabTitle ?? "文件浏览"
            titles.append(fileTitle.hasPrefix("📁") ? fileTitle : "📁 \(fileTitle)")
        }

        for (idx, title) in titles.enumerated() {
            let btn = UIButton(type: .custom)
            btn.tag = idx
            btn.setTitle(title, for: .normal)
            btn.contentEdgeInsets = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
            btn.addTarget(self, action: #selector(onTabButtonTapped(_:)), for: .touchUpInside)
            tabButtons.append(btn)
            tabStackView.addArrangedSubview(btn)
        }

        pagesContainer.backgroundColor = .clear
        pagesContainer.clipsToBounds = true
        pagesContainer.translatesAutoresizingMaskIntoConstraints = false
        hubContainer.addSubview(pagesContainer)

        NSLayoutConstraint.activate([
            hubContainer.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hubContainer.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            hubContainer.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.96),
            hubContainer.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.90),

            tabPanelBackground.topAnchor.constraint(equalTo: hubContainer.topAnchor),
            tabPanelBackground.bottomAnchor.constraint(equalTo: hubContainer.bottomAnchor),
            tabPanelBackground.leadingAnchor.constraint(equalTo: hubContainer.leadingAnchor),
            tabPanelBackground.trailingAnchor.constraint(equalTo: hubContainer.trailingAnchor),

            closeHookButton.topAnchor.constraint(equalTo: hubContainer.topAnchor, constant: 2),
            closeHookButton.trailingAnchor.constraint(equalTo: hubContainer.trailingAnchor, constant: -2),
            closeHookButton.widthAnchor.constraint(equalToConstant: 36),
            closeHookButton.heightAnchor.constraint(equalToConstant: 32),

            tabScrollView.topAnchor.constraint(equalTo: hubContainer.topAnchor),
            tabScrollView.leadingAnchor.constraint(equalTo: hubContainer.leadingAnchor),
            tabScrollView.trailingAnchor.constraint(equalTo: closeHookButton.leadingAnchor, constant: -6),
            tabScrollView.heightAnchor.constraint(equalToConstant: 36),

            tabStackView.topAnchor.constraint(equalTo: tabScrollView.topAnchor),
            tabStackView.bottomAnchor.constraint(equalTo: tabScrollView.bottomAnchor),
            tabStackView.leadingAnchor.constraint(equalTo: tabScrollView.leadingAnchor),
            tabStackView.trailingAnchor.constraint(equalTo: tabScrollView.trailingAnchor),
            tabStackView.heightAnchor.constraint(equalTo: tabScrollView.heightAnchor),

            pagesContainer.topAnchor.constraint(equalTo: hubContainer.topAnchor, constant: 37),
            pagesContainer.leadingAnchor.constraint(equalTo: hubContainer.leadingAnchor, constant: 2),
            pagesContainer.trailingAnchor.constraint(equalTo: hubContainer.trailingAnchor, constant: -2),
            pagesContainer.bottomAnchor.constraint(equalTo: hubContainer.bottomAnchor, constant: -2)
        ])
    }

    private func setupPages() {
        let net = HttpLogConsoleView()
        net.hostViewController = self
        self.networkView = net

        let dev = AppDeviceInfoView()
        dev.hostViewController = self
        self.deviceView = dev

        let cust = CustomPanelPageView()
        cust.setRegistration(customRegistration)
        cust.hostDialogController = self
        self.customView = cust

        var pages: [UIView] = [net, dev, cust]
        if let rootPath = config.fileBrowserRootPath {
            let fb = FileBrowserView(rootPath: rootPath)
            fb.hostViewController = self
            self.fileBrowserView = fb
            pages.append(fb)
        }
        self.pageViews = pages

        for page in pages {
            page.translatesAutoresizingMaskIntoConstraints = false
            page.isHidden = true
            pagesContainer.addSubview(page)
            NSLayoutConstraint.activate([
                page.topAnchor.constraint(equalTo: pagesContainer.topAnchor),
                page.bottomAnchor.constraint(equalTo: pagesContainer.bottomAnchor),
                page.leadingAnchor.constraint(equalTo: pagesContainer.leadingAnchor),
                page.trailingAnchor.constraint(equalTo: pagesContainer.trailingAnchor)
            ])
        }
    }

    @objc private func onTabButtonTapped(_ sender: UIButton) {
        guard !throttler.isThrottled(), sender.tag != currentTab else { return }
        selectTab(sender.tag, animated: true)
    }

    public func selectTab(_ index: Int, animated: Bool) {
        let safeIndex = (index >= 0 && index < tabCount) ? index : Self.TAB_NETWORK
        currentTab = safeIndex
        Self.lastSelectedTab = safeIndex

        for (i, btn) in tabButtons.enumerated() {
            let selected = (i == safeIndex)
            btn.setTitleColor(selected ? ShowLogTheme.actionBtn : ShowLogTheme.textSecondary, for: .normal)
            btn.titleLabel?.font = UIFont.systemFont(ofSize: 12.5, weight: selected ? .bold : .regular)
        }

        for (i, page) in pageViews.enumerated() {
            page.isHidden = (i != safeIndex)
        }

        if safeIndex == Self.TAB_DEVICE {
            deviceView?.setDeviceTabActive(true)
            deviceView?.loadData()
        } else {
            deviceView?.setDeviceTabActive(false)
            if safeIndex == Self.TAB_CUSTOM {
                customView?.renderCustomContent()
            }
        }

        if safeIndex < tabButtons.count {
            let targetBtn = tabButtons[safeIndex]
            tabScrollView.scrollRectToVisible(targetBtn.frame.insetBy(dx: -12, dy: 0), animated: animated)
        }
        DispatchQueue.main.async { [weak self] in
            self?.updateSelectedTabOutline()
        }
    }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView === tabScrollView {
            updateSelectedTabOutline()
        }
    }

    private func updateSelectedTabOutline() {
        guard currentTab >= 0, currentTab < tabButtons.count else { return }
        let selectedBtn = tabButtons[currentTab]
        tabStackView.layoutIfNeeded()
        let frameInBg = selectedBtn.convert(selectedBtn.bounds, to: tabPanelBackground)
        tabPanelBackground.setSelectedTab(tabLeft: frameInBg.minX, tabRight: frameInBg.maxX)
    }

    @objc private func handleCloseHub() {
        dismiss(animated: true)
    }
}

/// 支持向外扩展点击热区的按钮（对标 Android `TouchDelegate`）。
private final class ExpandedTouchButton: UIButton {
    var touchAreaPadding: CGFloat = 12.0

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let expandedBounds = bounds.insetBy(dx: -touchAreaPadding, dy: -touchAreaPadding)
        return expandedBounds.contains(point)
    }
}
#else
/// macOS 命令行测试环境常量与轻量门面控制器。
@objcMembers
public final class ShowLogHubViewController: UIViewController {
    public static let TAB_NETWORK: Int = 0
    public static let TAB_DEVICE: Int = 1
    public static let TAB_CUSTOM: Int = 2
    public static let TAB_FILE_BROWSER: Int = 3

    public private(set) static var lastSelectedTab: Int = TAB_NETWORK
    public let config: ShowLogConfig
    public let tabCount: Int
    public private(set) var currentTab: Int

    public init(initialTab: Int = ShowLogHubViewController.lastSelectedTab, config: ShowLogConfig = ShowLog.getConfig()) {
        self.config = config
        self.tabCount = (config.fileBrowserRootPath == nil) ? 3 : 4
        let resolvedTab = (initialTab >= 0 && initialTab < self.tabCount) ? initialTab : Self.TAB_NETWORK
        self.currentTab = resolvedTab
        Self.lastSelectedTab = resolvedTab
        super.init()
    }
}
#endif

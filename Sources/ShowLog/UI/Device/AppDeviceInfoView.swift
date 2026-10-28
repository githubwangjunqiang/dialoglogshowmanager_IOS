import Foundation
#if canImport(UIKit)
import UIKit

/// 设备与应用全景信息看板视图（对齐 Android `AppDeviceInfoView.java`）。
/// 支持：5 分类胶囊切换（全部 / 应用画像 / 操作系统 / 硬件屏幕 / 运行性能）、
/// 关键词实时搜索、2 秒性能定时自动刷新（仅在页面可见时运行）、一键复制与分享 Markdown 诊断报告。
@objcMembers
public final class AppDeviceInfoView: UIView, UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate {

    public weak var hostViewController: UIViewController?

    private let categories = [
        "全部",
        AppDeviceInfo.CATEGORY_APP,
        AppDeviceInfo.CATEGORY_OS,
        AppDeviceInfo.CATEGORY_HARDWARE,
        AppDeviceInfo.CATEGORY_PERFORMANCE
    ]

    private var selectedCategory = "全部"
    private var searchKeyword = ""
    private var currentInfo: AppDeviceInfo = AppDeviceInfo(items: [])
    private var displayedItems: [AppDeviceInfo.InfoItem] = []

    private var isDeviceTabActive = false
    private var refreshTimer: Timer?
    private let throttler = ClickThrottler(intervalMs: ShowLogTheme.throttleMs)

    private let countLabel = UILabel()
    private let refreshBtn = UIButton(type: .custom)
    private let exportBtn = UIButton(type: .custom)
    private let searchField = UITextField()
    private var categoryButtons: [UIButton] = []
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyLabel = UILabel()

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        loadData()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
        loadData()
    }

    deinit {
        stopRealtimeTimer()
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        updateTimerState()
    }

    /// 由 `ShowLogHubViewController` 通知当前是否处于设备信息 Tab。
    public func setDeviceTabActive(_ active: Bool) {
        guard isDeviceTabActive != active else { return }
        isDeviceTabActive = active
        updateTimerState()
    }

    public func loadData() {
        currentInfo = AppDeviceInfoCollector.collect()
        countLabel.text = "共 \(currentInfo.allItems.count) 项指标"
        applyFilter()
    }

    private func setupUI() {
        backgroundColor = .clear

        // Row 1: Count + Refresh + Export Markdown
        let topBar = UIView()
        topBar.translatesAutoresizingMaskIntoConstraints = false

        countLabel.font = UIFont.systemFont(ofSize: 12, weight: .bold)
        countLabel.textColor = ShowLogTheme.textSecondary
        countLabel.translatesAutoresizingMaskIntoConstraints = false

        refreshBtn.setTitle("🔄 刷新", for: .normal)
        refreshBtn.setTitleColor(ShowLogTheme.textPrimary, for: .normal)
        refreshBtn.titleLabel?.font = UIFont.systemFont(ofSize: 11.5, weight: .semibold)
        refreshBtn.backgroundColor = ShowLogTheme.bgPill
        refreshBtn.layer.cornerRadius = 6
        refreshBtn.contentEdgeInsets = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        refreshBtn.translatesAutoresizingMaskIntoConstraints = false
        refreshBtn.addTarget(self, action: #selector(handleRefresh), for: .touchUpInside)

        exportBtn.setTitle("📋 导出诊断报告 (MD)", for: .normal)
        exportBtn.setTitleColor(ShowLogTheme.textOnAccent, for: .normal)
        exportBtn.titleLabel?.font = UIFont.systemFont(ofSize: 11.5, weight: .bold)
        exportBtn.backgroundColor = ShowLogTheme.bgPillSelected
        exportBtn.layer.cornerRadius = 6
        exportBtn.contentEdgeInsets = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        exportBtn.translatesAutoresizingMaskIntoConstraints = false
        exportBtn.addTarget(self, action: #selector(handleExportMarkdown(_:)), for: .touchUpInside)

        topBar.addSubview(countLabel)
        topBar.addSubview(refreshBtn)
        topBar.addSubview(exportBtn)

        // Row 2: Search input
        searchField.font = UIFont.systemFont(ofSize: 12)
        searchField.textColor = ShowLogTheme.textPrimary
        searchField.backgroundColor = ShowLogTheme.bgCard
        searchField.layer.cornerRadius = 6
        searchField.layer.borderWidth = 1
        searchField.layer.borderColor = ShowLogTheme.bgCardStroke.cgColor
        searchField.clearButtonMode = .whileEditing
        searchField.returnKeyType = .done
        searchField.delegate = self
        searchField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 1))
        searchField.leftViewMode = .always
        searchField.attributedPlaceholder = NSAttributedString(
            string: "🔍 搜索属性名称或参数值（如 内存、分辨率、IP、版本）...",
            attributes: [.foregroundColor: ShowLogTheme.textTertiary]
        )
        searchField.addTarget(self, action: #selector(onSearchTextChanged), for: .editingChanged)
        searchField.translatesAutoresizingMaskIntoConstraints = false

        // Row 3: 5 Category Pills
        let categoryScroll = UIScrollView()
        categoryScroll.showsHorizontalScrollIndicator = false
        categoryScroll.translatesAutoresizingMaskIntoConstraints = false

        let categoryStack = UIStackView()
        categoryStack.axis = .horizontal
        categoryStack.spacing = 6
        categoryStack.translatesAutoresizingMaskIntoConstraints = false
        categoryScroll.addSubview(categoryStack)

        for (index, cat) in categories.enumerated() {
            let btn = UIButton(type: .custom)
            btn.setTitle(cat, for: .normal)
            btn.tag = index
            btn.titleLabel?.font = UIFont.systemFont(ofSize: 11.5, weight: .medium)
            btn.layer.cornerRadius = 6
            btn.contentEdgeInsets = UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
            btn.addTarget(self, action: #selector(onCategoryTapped(_:)), for: .touchUpInside)
            categoryButtons.append(btn)
            categoryStack.addArrangedSubview(btn)
        }
        updateCategoryButtonsUI()

        // TableView
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 56
        tableView.keyboardDismissMode = .onDrag
        tableView.register(AppDeviceInfoCell.self, forCellReuseIdentifier: AppDeviceInfoCell.reuseIdentifier)
        tableView.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.text = "未找到匹配的设备或系统指标"
        emptyLabel.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        emptyLabel.textColor = ShowLogTheme.textTertiary
        emptyLabel.textAlignment = .center
        emptyLabel.isHidden = true
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(topBar)
        addSubview(searchField)
        addSubview(categoryScroll)
        addSubview(tableView)
        addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            topBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            topBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            topBar.heightAnchor.constraint(equalToConstant: 28),

            countLabel.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 2),
            countLabel.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),

            exportBtn.trailingAnchor.constraint(equalTo: topBar.trailingAnchor),
            exportBtn.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            exportBtn.heightAnchor.constraint(equalToConstant: 26),

            refreshBtn.trailingAnchor.constraint(equalTo: exportBtn.leadingAnchor, constant: -6),
            refreshBtn.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            refreshBtn.heightAnchor.constraint(equalToConstant: 26),

            searchField.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 6),
            searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            searchField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            searchField.heightAnchor.constraint(equalToConstant: 30),

            categoryScroll.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 6),
            categoryScroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            categoryScroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            categoryScroll.heightAnchor.constraint(equalToConstant: 28),

            categoryStack.topAnchor.constraint(equalTo: categoryScroll.topAnchor),
            categoryStack.bottomAnchor.constraint(equalTo: categoryScroll.bottomAnchor),
            categoryStack.leadingAnchor.constraint(equalTo: categoryScroll.leadingAnchor),
            categoryStack.trailingAnchor.constraint(equalTo: categoryScroll.trailingAnchor),
            categoryStack.heightAnchor.constraint(equalTo: categoryScroll.heightAnchor),

            tableView.topAnchor.constraint(equalTo: categoryScroll.bottomAnchor, constant: 6),
            tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: tableView.centerYAnchor)
        ])
    }

    private func updateCategoryButtonsUI() {
        for (idx, btn) in categoryButtons.enumerated() {
            let isSelected = (categories[idx] == selectedCategory)
            btn.backgroundColor = isSelected ? ShowLogTheme.bgPillSelected : ShowLogTheme.bgPill
            btn.setTitleColor(isSelected ? ShowLogTheme.textOnAccent : ShowLogTheme.textSecondary, for: .normal)
            btn.titleLabel?.font = UIFont.systemFont(ofSize: 11.5, weight: isSelected ? .bold : .regular)
        }
    }

    private func applyFilter() {
        let lowerKw = searchKeyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let catItems = currentInfo.getItemsByCategory(selectedCategory)

        if lowerKw.isEmpty {
            displayedItems = catItems
        } else {
            displayedItems = catItems.filter { item in
                item.key.lowercased().contains(lowerKw)
                    || item.value.lowercased().contains(lowerKw)
                    || item.category.lowercased().contains(lowerKw)
            }
        }

        emptyLabel.isHidden = !displayedItems.isEmpty
        tableView.isHidden = displayedItems.isEmpty
        tableView.reloadData()
    }

    // MARK: - 2s Realtime Performance Timer

    private func updateTimerState() {
        stopRealtimeTimer()
        guard isDeviceTabActive, window != nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isDeviceTabActive, self.window != nil else { return }
            self.loadData()
        }
        self.refreshTimer = timer
    }

    private func stopRealtimeTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - UITableViewDataSource & Delegate

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return displayedItems.count
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: AppDeviceInfoCell.reuseIdentifier, for: indexPath) as? AppDeviceInfoCell else {
            return UITableViewCell()
        }
        cell.configure(with: displayedItems[indexPath.row])
        return cell
    }

    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let item = displayedItems[indexPath.row]
        UIPasteboard.general.string = item.value
        ToastView.show("已复制 \(item.key): \(item.value)", in: self)
    }

    // MARK: - Actions

    @objc private func handleRefresh() {
        guard !throttler.isThrottled() else { return }
        loadData()
        ToastView.show("设备与运行状态已刷新", in: self)
    }

    @objc private func handleExportMarkdown(_ sender: UIButton) {
        guard !throttler.isThrottled() else { return }
        let markdown = AppDeviceInfoExporter.exportToMarkdown(currentInfo)
        UIPasteboard.general.string = markdown
        ToastView.show("📋 全景诊断报告 (Markdown) 已复制到剪贴板！", in: self)
    }

    @objc private func onCategoryTapped(_ sender: UIButton) {
        guard !throttler.isThrottled() else { return }
        let cat = categories[sender.tag]
        guard selectedCategory != cat else { return }
        selectedCategory = cat
        updateCategoryButtonsUI()
        applyFilter()
    }

    @objc private func onSearchTextChanged() {
        searchKeyword = searchField.text ?? ""
        applyFilter()
    }

    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
#endif

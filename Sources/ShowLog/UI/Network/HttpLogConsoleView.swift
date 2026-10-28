import Foundation
#if canImport(UIKit)
import UIKit

/// 网络日志调试控制台主视图组件（1:1 对齐 Android `HttpLogConsoleView.java`）。
/// 涵盖：日期选择与日历弹框、列表/分组两态滑块、倒序/正序两态滑块、独立搜索弹框与生效关键词胶囊、
/// 全部/成功/失败状态筛选、实时推流监听、长按单条/分组删除、当天/全量清理、查询代次防错乱。
@objcMembers
public final class HttpLogConsoleView: UIView, OnNewLogListener, UITableViewDataSource, UITableViewDelegate {

    private static let FILTER_ALL = 0
    private static let FILTER_SUCCESS = 1
    private static let FILTER_ERROR = 2

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()

    public weak var hostViewController: UIViewController?

    private var currentDate = Date()
    private var isSortAsc = false
    private var isGroupMode = false
    private var currentFilter = FILTER_ALL
    private var searchKeyword = ""
    private var queryGeneration = 0

    /// 记忆分组模式下已展开的接口 key (`method + "_" + path`)，实时推入新日志时保持展开态不丢失。
    private var expandedGroupKeys = Set<String>()

    private var rawRecords: [HttpLogRecord] = []
    private var filteredRecords: [HttpLogRecord] = []
    private var groupItems: [HttpLogGroupItem] = []

    private let throttler = ClickThrottler(intervalMs: ShowLogTheme.throttleMs)

    // UI Controls
    private let prevDateBtn = UIButton(type: .custom)
    private let dateTitleBtn = UIButton(type: .custom)
    private let nextDateBtn = UIButton(type: .custom)
    private let viewModeSwitch = ShowLogToggleSwitch()
    private let sortSwitch = ShowLogToggleSwitch()
    private let searchBtn = UIButton(type: .custom)
    private let clearBtn = UIButton(type: .custom)
    private let searchKeywordChip = UIButton(type: .custom)

    private let filterAllBtn = UIButton(type: .custom)
    private let filterSuccessBtn = UIButton(type: .custom)
    private let filterErrorBtn = UIButton(type: .custom)

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private let emptyLabel = UILabel()

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        loadDataForCurrentDay()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
        loadDataForCurrentDay()
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            HttpLogRepository.shared.registerNewLogListener(self)
        } else {
            HttpLogRepository.shared.unregisterNewLogListener(self)
        }
    }

    deinit {
        HttpLogRepository.shared.unregisterNewLogListener(self)
    }

    private func setupUI() {
        backgroundColor = .clear

        // Row 1: Date bar + Clear button
        let row1 = UIView()
        row1.translatesAutoresizingMaskIntoConstraints = false

        prevDateBtn.setTitle("◀", for: .normal)
        prevDateBtn.setTitleColor(ShowLogTheme.textSecondary, for: .normal)
        prevDateBtn.titleLabel?.font = UIFont.systemFont(ofSize: 12, weight: .bold)
        prevDateBtn.backgroundColor = ShowLogTheme.bgPill
        prevDateBtn.layer.cornerRadius = 6
        prevDateBtn.translatesAutoresizingMaskIntoConstraints = false
        prevDateBtn.addTarget(self, action: #selector(handlePrevDay), for: .touchUpInside)

        dateTitleBtn.setTitleColor(ShowLogTheme.textPrimary, for: .normal)
        dateTitleBtn.titleLabel?.font = ShowLogTheme.monospacedFont(size: 12, weight: .bold)
        dateTitleBtn.backgroundColor = ShowLogTheme.bgCard
        dateTitleBtn.layer.cornerRadius = 6
        dateTitleBtn.layer.borderWidth = 1
        dateTitleBtn.layer.borderColor = ShowLogTheme.bgCardStroke.cgColor
        dateTitleBtn.contentEdgeInsets = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        dateTitleBtn.translatesAutoresizingMaskIntoConstraints = false
        dateTitleBtn.addTarget(self, action: #selector(handlePickDate), for: .touchUpInside)

        nextDateBtn.setTitle("▶", for: .normal)
        nextDateBtn.setTitleColor(ShowLogTheme.textSecondary, for: .normal)
        nextDateBtn.titleLabel?.font = UIFont.systemFont(ofSize: 12, weight: .bold)
        nextDateBtn.backgroundColor = ShowLogTheme.bgPill
        nextDateBtn.layer.cornerRadius = 6
        nextDateBtn.translatesAutoresizingMaskIntoConstraints = false
        nextDateBtn.addTarget(self, action: #selector(handleNextDay), for: .touchUpInside)

        clearBtn.setTitle("🗑️ 清理", for: .normal)
        clearBtn.setTitleColor(ShowLogTheme.status5xx, for: .normal)
        clearBtn.titleLabel?.font = UIFont.systemFont(ofSize: 11.5, weight: .bold)
        clearBtn.backgroundColor = ShowLogTheme.bgPill
        clearBtn.layer.cornerRadius = 6
        clearBtn.contentEdgeInsets = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        clearBtn.translatesAutoresizingMaskIntoConstraints = false
        clearBtn.addTarget(self, action: #selector(handleShowClearOptions), for: .touchUpInside)

        row1.addSubview(prevDateBtn)
        row1.addSubview(dateTitleBtn)
        row1.addSubview(nextDateBtn)
        row1.addSubview(clearBtn)

        // Row 2: ViewMode switch + Sort switch + Search button + Keyword chip
        let row2 = UIView()
        row2.translatesAutoresizingMaskIntoConstraints = false

        viewModeSwitch.setLabels(left: "列表", right: "分组")
        viewModeSwitch.setChecked(false, animated: false)
        viewModeSwitch.translatesAutoresizingMaskIntoConstraints = false
        viewModeSwitch.onCheckedChanged = { [weak self] isChecked in
            guard let self = self, self.isGroupMode != isChecked else { return }
            self.isGroupMode = isChecked
            self.applyFilterAndRender()
        }

        sortSwitch.setLabels(left: "倒序", right: "正序")
        sortSwitch.setChecked(false, animated: false)
        sortSwitch.translatesAutoresizingMaskIntoConstraints = false
        sortSwitch.onCheckedChanged = { [weak self] isChecked in
            guard let self = self, self.isSortAsc != isChecked else { return }
            self.isSortAsc = isChecked
            self.loadDataForCurrentDay()
        }

        searchBtn.setTitle("🔍", for: .normal)
        searchBtn.titleLabel?.font = UIFont.systemFont(ofSize: 13)
        searchBtn.backgroundColor = ShowLogTheme.bgPill
        searchBtn.layer.cornerRadius = 6
        searchBtn.layer.borderWidth = 1
        searchBtn.layer.borderColor = ShowLogTheme.bgCardStroke.cgColor
        searchBtn.translatesAutoresizingMaskIntoConstraints = false
        searchBtn.addTarget(self, action: #selector(handleOpenSearch), for: .touchUpInside)

        searchKeywordChip.setTitleColor(ShowLogTheme.actionBtn, for: .normal)
        searchKeywordChip.titleLabel?.font = UIFont.systemFont(ofSize: 11, weight: .semibold)
        searchKeywordChip.titleLabel?.lineBreakMode = .byTruncatingTail
        searchKeywordChip.backgroundColor = ShowLogTheme.bgCard
        searchKeywordChip.layer.cornerRadius = 6
        searchKeywordChip.layer.borderWidth = 1
        searchKeywordChip.layer.borderColor = ShowLogTheme.actionBtn.withAlphaComponent(0.5).cgColor
        searchKeywordChip.contentEdgeInsets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        searchKeywordChip.isHidden = true
        searchKeywordChip.translatesAutoresizingMaskIntoConstraints = false
        searchKeywordChip.addTarget(self, action: #selector(handleOpenSearch), for: .touchUpInside)

        row2.addSubview(viewModeSwitch)
        row2.addSubview(sortSwitch)
        row2.addSubview(searchBtn)
        row2.addSubview(searchKeywordChip)

        // Row 3: Status Filter Segmented Bar
        let filterContainer = UIView()
        filterContainer.backgroundColor = ShowLogTheme.bgPill
        filterContainer.layer.cornerRadius = 8
        filterContainer.layer.borderWidth = 1
        filterContainer.layer.borderColor = ShowLogTheme.bgCardStroke.cgColor
        filterContainer.translatesAutoresizingMaskIntoConstraints = false

        configureFilterButton(filterAllBtn, tag: Self.FILTER_ALL)
        configureFilterButton(filterSuccessBtn, tag: Self.FILTER_SUCCESS)
        configureFilterButton(filterErrorBtn, tag: Self.FILTER_ERROR)

        let filterStack = UIStackView(arrangedSubviews: [filterAllBtn, filterSuccessBtn, filterErrorBtn])
        filterStack.axis = .horizontal
        filterStack.distribution = .fillEqually
        filterStack.spacing = 2
        filterStack.translatesAutoresizingMaskIntoConstraints = false
        filterContainer.addSubview(filterStack)

        // TableView & Empty State
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 68
        tableView.register(HttpLogFlatCell.self, forCellReuseIdentifier: HttpLogFlatCell.reuseIdentifier)
        tableView.register(HttpLogGroupCell.self, forCellReuseIdentifier: HttpLogGroupCell.reuseIdentifier)
        tableView.translatesAutoresizingMaskIntoConstraints = false

        loadingIndicator.color = ShowLogTheme.actionBtn
        loadingIndicator.hidesWhenStopped = true
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        emptyLabel.textColor = ShowLogTheme.textTertiary
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 2
        emptyLabel.isHidden = true
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(row1)
        addSubview(row2)
        addSubview(filterContainer)
        addSubview(tableView)
        addSubview(emptyLabel)
        addSubview(loadingIndicator)

        NSLayoutConstraint.activate([
            row1.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            row1.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            row1.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            row1.heightAnchor.constraint(equalToConstant: 28),

            prevDateBtn.leadingAnchor.constraint(equalTo: row1.leadingAnchor),
            prevDateBtn.centerYAnchor.constraint(equalTo: row1.centerYAnchor),
            prevDateBtn.widthAnchor.constraint(equalToConstant: 30),
            prevDateBtn.heightAnchor.constraint(equalToConstant: 26),

            dateTitleBtn.leadingAnchor.constraint(equalTo: prevDateBtn.trailingAnchor, constant: 4),
            dateTitleBtn.centerYAnchor.constraint(equalTo: row1.centerYAnchor),
            dateTitleBtn.heightAnchor.constraint(equalToConstant: 26),

            nextDateBtn.leadingAnchor.constraint(equalTo: dateTitleBtn.trailingAnchor, constant: 4),
            nextDateBtn.centerYAnchor.constraint(equalTo: row1.centerYAnchor),
            nextDateBtn.widthAnchor.constraint(equalToConstant: 30),
            nextDateBtn.heightAnchor.constraint(equalToConstant: 26),

            clearBtn.trailingAnchor.constraint(equalTo: row1.trailingAnchor),
            clearBtn.centerYAnchor.constraint(equalTo: row1.centerYAnchor),
            clearBtn.heightAnchor.constraint(equalToConstant: 26),

            row2.topAnchor.constraint(equalTo: row1.bottomAnchor, constant: 6),
            row2.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            row2.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            row2.heightAnchor.constraint(equalToConstant: 28),

            viewModeSwitch.leadingAnchor.constraint(equalTo: row2.leadingAnchor),
            viewModeSwitch.centerYAnchor.constraint(equalTo: row2.centerYAnchor),
            viewModeSwitch.widthAnchor.constraint(equalToConstant: 88),
            viewModeSwitch.heightAnchor.constraint(equalToConstant: 26),

            sortSwitch.leadingAnchor.constraint(equalTo: viewModeSwitch.trailingAnchor, constant: 6),
            sortSwitch.centerYAnchor.constraint(equalTo: row2.centerYAnchor),
            sortSwitch.widthAnchor.constraint(equalToConstant: 88),
            sortSwitch.heightAnchor.constraint(equalToConstant: 26),

            searchBtn.leadingAnchor.constraint(equalTo: sortSwitch.trailingAnchor, constant: 6),
            searchBtn.centerYAnchor.constraint(equalTo: row2.centerYAnchor),
            searchBtn.widthAnchor.constraint(equalToConstant: 32),
            searchBtn.heightAnchor.constraint(equalToConstant: 26),

            searchKeywordChip.leadingAnchor.constraint(equalTo: searchBtn.trailingAnchor, constant: 6),
            searchKeywordChip.trailingAnchor.constraint(lessThanOrEqualTo: row2.trailingAnchor),
            searchKeywordChip.centerYAnchor.constraint(equalTo: row2.centerYAnchor),
            searchKeywordChip.heightAnchor.constraint(equalToConstant: 24),

            filterContainer.topAnchor.constraint(equalTo: row2.bottomAnchor, constant: 6),
            filterContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            filterContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            filterContainer.heightAnchor.constraint(equalToConstant: 30),

            filterStack.topAnchor.constraint(equalTo: filterContainer.topAnchor, constant: 2),
            filterStack.bottomAnchor.constraint(equalTo: filterContainer.bottomAnchor, constant: -2),
            filterStack.leadingAnchor.constraint(equalTo: filterContainer.leadingAnchor, constant: 2),
            filterStack.trailingAnchor.constraint(equalTo: filterContainer.trailingAnchor, constant: -2),

            tableView.topAnchor.constraint(equalTo: filterContainer.bottomAnchor, constant: 6),
            tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: tableView.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            emptyLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),

            loadingIndicator.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: tableView.centerYAnchor)
        ])

        updateFilterButtonsUI(total: 0, success: 0, error: 0)
    }

    private func configureFilterButton(_ button: UIButton, tag: Int) {
        button.tag = tag
        button.layer.cornerRadius = 6
        button.titleLabel?.font = UIFont.systemFont(ofSize: 11.5, weight: .medium)
        button.addTarget(self, action: #selector(onFilterTabTapped(_:)), for: .touchUpInside)
    }

    // MARK: - Data Loading & Filtering

    public func reloadData() {
        loadDataForCurrentDay()
    }

    private func loadDataForCurrentDay() {
        updateDateButtonTitle()
        loadingIndicator.startAnimating()
        emptyLabel.isHidden = true

        queryGeneration += 1
        let expectedGen = queryGeneration
        let (startMs, endMs) = Self.dayTimeRange(for: currentDate)

        HttpLogRepository.shared.queryLogsAsync(
            startTime: startMs,
            endTime: endMs,
            isAsc: isSortAsc,
            onSuccess: { [weak self] records in
                guard let self = self, expectedGen == self.queryGeneration else { return }
                self.loadingIndicator.stopAnimating()
                self.rawRecords = records
                self.applyFilterAndRender()
            },
            onError: { [weak self] err in
                guard let self = self, expectedGen == self.queryGeneration else { return }
                self.loadingIndicator.stopAnimating()
                ToastView.show("加载日志异常: \(err.localizedDescription)", in: self)
            }
        )
    }

    private func updateDateButtonTitle() {
        let isToday = Calendar.current.isDateInToday(currentDate)
        let dateStr = Self.dateFormatter.string(from: currentDate)
        let title = isToday ? "今天 (\(dateStr))" : dateStr
        dateTitleBtn.setTitle(title, for: .normal)
    }

    private func applyFilterAndRender() {
        filteredRecords.removeAll()
        var matchedTotal = 0
        var successCount = 0
        var failedCount = 0

        let lowerKw = searchKeyword.lowercased()

        for record in rawRecords {
            if !Self.matchesKeyword(record: record, lowerKeyword: lowerKw) {
                continue
            }
            matchedTotal += 1
            if record.success {
                successCount += 1
            } else {
                failedCount += 1
            }

            if currentFilter == Self.FILTER_SUCCESS && !record.success {
                continue
            }
            if currentFilter == Self.FILTER_ERROR && record.success {
                continue
            }
            filteredRecords.append(record)
        }

        updateFilterButtonsUI(total: matchedTotal, success: successCount, error: failedCount)
        updateSearchKeywordChipUI()

        if filteredRecords.isEmpty {
            let hasFilter = !searchKeyword.isEmpty || currentFilter != Self.FILTER_ALL
            emptyLabel.text = hasFilter ? "当前筛选条件下无匹配的网络日志" : "当日暂无网络请求记录"
            emptyLabel.isHidden = false
            tableView.isHidden = true
            tableView.reloadData()
            return
        }

        emptyLabel.isHidden = true
        tableView.isHidden = false

        if isGroupMode {
            groupItems = buildGroupItems(from: filteredRecords)
        }
        tableView.reloadData()
    }

    public static func matchesKeyword(record: HttpLogRecord, lowerKeyword: String) -> Bool {
        if lowerKeyword.isEmpty { return true }
        if record.url.lowercased().contains(lowerKeyword) { return true }
        if record.host.lowercased().contains(lowerKeyword) { return true }
        if record.path.lowercased().contains(lowerKeyword) { return true }
        if "\(record.statusCode)".contains(lowerKeyword) { return true }
        if record.message.lowercased().contains(lowerKeyword) { return true }
        return false
    }

    private func buildGroupItems(from records: [HttpLogRecord]) -> [HttpLogGroupItem] {
        var orderedKeys: [String] = []
        var map: [String: HttpLogGroupItem] = [:]

        for record in records {
            let key = "\(record.method)_\(record.path)"
            if let existing = map[key] {
                existing.addRecord(record)
            } else {
                let group = HttpLogGroupItem(path: record.path, method: record.method, host: record.host)
                group.isExpanded = expandedGroupKeys.contains(key)
                group.addRecord(record)
                map[key] = group
                orderedKeys.append(key)
            }
        }
        return orderedKeys.compactMap { map[$0] }
    }

    private func updateFilterButtonsUI(total: Int, success: Int, error: Int) {
        filterAllBtn.setTitle("全部 (\(total))", for: .normal)
        filterSuccessBtn.setTitle("成功 (\(success))", for: .normal)
        filterErrorBtn.setTitle("失败/异常 (\(error))", for: .normal)

        filterAllBtn.backgroundColor = .clear
        filterAllBtn.setTitleColor(ShowLogTheme.textSecondary, for: .normal)
        filterAllBtn.titleLabel?.font = UIFont.systemFont(ofSize: 11.5, weight: .regular)

        filterSuccessBtn.backgroundColor = .clear
        filterSuccessBtn.setTitleColor(ShowLogTheme.textSecondary, for: .normal)
        filterSuccessBtn.titleLabel?.font = UIFont.systemFont(ofSize: 11.5, weight: .regular)

        filterErrorBtn.backgroundColor = .clear
        filterErrorBtn.setTitleColor(error > 0 ? ShowLogTheme.statusError : ShowLogTheme.textSecondary, for: .normal)
        filterErrorBtn.titleLabel?.font = UIFont.systemFont(ofSize: 11.5, weight: .regular)

        switch currentFilter {
        case Self.FILTER_ALL:
            filterAllBtn.backgroundColor = ShowLogTheme.bgPillSelected
            filterAllBtn.setTitleColor(ShowLogTheme.textOnAccent, for: .normal)
            filterAllBtn.titleLabel?.font = UIFont.systemFont(ofSize: 11.5, weight: .bold)
        case Self.FILTER_SUCCESS:
            filterSuccessBtn.backgroundColor = ShowLogTheme.bgPillSelected
            filterSuccessBtn.setTitleColor(ShowLogTheme.textOnAccent, for: .normal)
            filterSuccessBtn.titleLabel?.font = UIFont.systemFont(ofSize: 11.5, weight: .bold)
        case Self.FILTER_ERROR:
            filterErrorBtn.backgroundColor = ShowLogTheme.statusError
            filterErrorBtn.setTitleColor(ShowLogTheme.textPrimary, for: .normal)
            filterErrorBtn.titleLabel?.font = UIFont.systemFont(ofSize: 11.5, weight: .bold)
        default:
            break
        }
    }

    private func updateSearchKeywordChipUI() {
        if searchKeyword.isEmpty {
            searchKeywordChip.isHidden = true
        } else {
            searchKeywordChip.isHidden = false
            searchKeywordChip.setTitle("筛选: \(searchKeyword) ✕", for: .normal)
        }
    }

    // MARK: - OnNewLogListener

    public func onNewLog(_ record: HttpLogRecord) {
        let (startMs, endMs) = Self.dayTimeRange(for: currentDate)
        guard record.timestamp >= startMs && record.timestamp <= endMs else { return }

        if isSortAsc {
            rawRecords.append(record)
        } else {
            rawRecords.insert(record, at: 0)
        }
        applyFilterAndRender()
    }

    // MARK: - UITableViewDataSource & UITableViewDelegate

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return isGroupMode ? groupItems.count : filteredRecords.count
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if isGroupMode {
            guard let cell = tableView.dequeueReusableCell(withIdentifier: HttpLogGroupCell.reuseIdentifier, for: indexPath) as? HttpLogGroupCell else {
                return UITableViewCell()
            }
            let group = groupItems[indexPath.row]
            cell.configure(with: group)
            cell.onToggleExpand = { [weak self] item in
                guard let self = self else { return }
                let key = "\(item.method)_\(item.path)"
                item.isExpanded.toggle()
                if item.isExpanded {
                    self.expandedGroupKeys.insert(key)
                } else {
                    self.expandedGroupKeys.remove(key)
                }
                self.tableView.reloadRows(at: [indexPath], with: .fade)
            }
            cell.onGroupLongPressDelete = { [weak self] item in
                self?.confirmDeleteGroup(item)
            }
            cell.onChildSelect = { [weak self] rec in
                self?.presentDetailDialog(for: rec)
            }
            cell.onChildLongPressDelete = { [weak self] rec in
                self?.confirmDeleteSingleRecord(rec)
            }
            return cell
        } else {
            guard let cell = tableView.dequeueReusableCell(withIdentifier: HttpLogFlatCell.reuseIdentifier, for: indexPath) as? HttpLogFlatCell else {
                return UITableViewCell()
            }
            let record = filteredRecords[indexPath.row]
            cell.configure(with: record)
            cell.onLongPressDelete = { [weak self] rec in
                self?.confirmDeleteSingleRecord(rec)
            }
            return cell
        }
    }

    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard !isGroupMode else { return }
        guard !throttler.isThrottled() else { return }
        let record = filteredRecords[indexPath.row]
        presentDetailDialog(for: record)
    }

    private func presentDetailDialog(for record: HttpLogRecord) {
        guard let hostVC = hostViewController ?? findResponderViewController() else { return }
        let detailVC = HttpLogDetailViewController(record: record)
        hostVC.present(detailVC, animated: true)
    }

    // MARK: - User Actions & Dialogs

    @objc private func handlePrevDay() {
        guard !throttler.isThrottled() else { return }
        if let prev = Calendar.current.date(byAdding: .day, value: -1, to: currentDate) {
            currentDate = prev
            loadDataForCurrentDay()
        }
    }

    @objc private func handleNextDay() {
        guard !throttler.isThrottled() else { return }
        if let next = Calendar.current.date(byAdding: .day, value: 1, to: currentDate) {
            currentDate = next
            loadDataForCurrentDay()
        }
    }

    @objc private func handlePickDate() {
        guard !throttler.isThrottled(),
              let hostVC = hostViewController ?? findResponderViewController() else { return }

        let alert = UIAlertController(title: "选择日志日期", message: "\n\n\n\n\n\n\n\n", preferredStyle: .alert)
        if #available(iOS 13.0, *) {
            alert.overrideUserInterfaceStyle = .dark
        }
        let picker = UIDatePicker()
        picker.datePickerMode = .date
        if #available(iOS 13.4, *) {
            picker.preferredDatePickerStyle = .wheels
        }
        picker.date = currentDate
        picker.translatesAutoresizingMaskIntoConstraints = false
        alert.view.addSubview(picker)

        NSLayoutConstraint.activate([
            picker.centerXAnchor.constraint(equalTo: alert.view.centerXAnchor),
            picker.topAnchor.constraint(equalTo: alert.view.topAnchor, constant: 45),
            picker.widthAnchor.constraint(equalToConstant: 250),
            picker.heightAnchor.constraint(equalToConstant: 150)
        ])

        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "确定", style: .default) { [weak self] _ in
            self?.currentDate = picker.date
            self?.loadDataForCurrentDay()
        })
        hostVC.present(alert, animated: true)
    }

    @objc private func handleOpenSearch() {
        guard !throttler.isThrottled() else { return }
        let container = (hostViewController?.view) ?? self
        SearchKeywordAlertView.show(
            in: container,
            initialKeyword: searchKeyword,
            onConfirm: { [weak self] kw in
                self?.searchKeyword = kw
                self?.applyFilterAndRender()
            },
            onClear: { [weak self] in
                self?.searchKeyword = ""
                self?.applyFilterAndRender()
            }
        )
    }

    @objc private func onFilterTabTapped(_ sender: UIButton) {
        guard !throttler.isThrottled(), currentFilter != sender.tag else { return }
        currentFilter = sender.tag
        applyFilterAndRender()
    }

    @objc private func handleShowClearOptions() {
        guard !throttler.isThrottled(),
              let hostVC = hostViewController ?? findResponderViewController() else { return }

        let dateStr = Self.dateFormatter.string(from: currentDate)
        let alert = UIAlertController(
            title: "清理网络日志",
            message: "请选择需要清理的日志范围（清理后不可恢复）",
            preferredStyle: .alert
        )
        if #available(iOS 13.0, *) {
            alert.overrideUserInterfaceStyle = .dark
        }
        alert.addAction(UIAlertAction(title: "仅清理 \(dateStr) 当天日志", style: .default) { [weak self] _ in
            guard let self = self else { return }
            let (startMs, endMs) = Self.dayTimeRange(for: self.currentDate)
            HttpLogRepository.shared.clearRangeAsync(startTime: startMs, endTime: endMs) {
                ToastView.show("已清理 \(dateStr) 当天日志", in: self)
                self.loadDataForCurrentDay()
            }
        })
        alert.addAction(UIAlertAction(title: "清空全部历史网络日志", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            HttpLogRepository.shared.clearAllAsync {
                ToastView.show("已清空所有历史网络日志", in: self)
                self.loadDataForCurrentDay()
            }
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        hostVC.present(alert, animated: true)
    }

    private func confirmDeleteSingleRecord(_ record: HttpLogRecord) {
        guard let hostVC = hostViewController ?? findResponderViewController() else { return }
        let pathStr = !record.path.isEmpty ? record.path : record.url
        let statusStr = record.statusCode < 0 ? "FAILED" : "\(record.statusCode)"
        let msg = "确定删除这条网络日志记录吗？\n\n• 方式: \(record.method)\n• 接口: \(pathStr)\n• 状态: \(statusStr) (\(record.durationMs) ms)"

        let alert = UIAlertController(title: "删除单条日志", message: msg, preferredStyle: .alert)
        if #available(iOS 13.0, *) {
            alert.overrideUserInterfaceStyle = .dark
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "确认删除", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            HttpLogRepository.shared.deleteRecordAsync(record) {
                ToastView.show("已删除该条日志", in: self)
                self.loadDataForCurrentDay()
            }
        })
        hostVC.present(alert, animated: true)
    }

    private func confirmDeleteGroup(_ group: HttpLogGroupItem) {
        guard let hostVC = hostViewController ?? findResponderViewController() else { return }
        let dateStr = Self.dateFormatter.string(from: currentDate)
        let msg = "确定删除该接口分组下的全部 \(group.totalCount) 条日志吗？\n\n• 接口: [\(group.method)] \(group.path)\n• 范围: 仅删除 \(dateStr) 当天该接口的日志记录。"

        let alert = UIAlertController(title: "删除分组网络日志", message: msg, preferredStyle: .alert)
        if #available(iOS 13.0, *) {
            alert.overrideUserInterfaceStyle = .dark
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "删除全部分组", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            HttpLogRepository.shared.deleteRecordsBatchAsync(group.records) {
                ToastView.show("已删除 [\(group.path)] 分组下的 \(group.totalCount) 条日志", in: self)
                self.loadDataForCurrentDay()
            }
        })
        hostVC.present(alert, animated: true)
    }

    public static func dayTimeRange(for date: Date) -> (startMs: Int64, endMs: Int64) {
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: date)
        let startMs = Int64(startOfDay.timeIntervalSince1970 * 1000.0)
        let endMs = startMs + 86_400_000 - 1
        return (startMs, endMs)
    }

    private func findResponderViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let next = responder?.next {
            if let vc = next as? UIViewController {
                return vc
            }
            responder = next
        }
        return nil
    }
}
#endif

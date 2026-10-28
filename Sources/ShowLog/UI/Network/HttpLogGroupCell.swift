import Foundation
#if canImport(UIKit)
import UIKit

/// 接口折叠分组卡片 Cell（严格对齐 Android `HttpLogGroupAdapter.java`）。
/// 为什么这样做：
/// 1. 按接口 `method + path` 聚合，展示调用总次数与最新状态码/耗时摘要（当最新一次 `latestSuccess == false` 时标红 `#EF4444`）；
/// 2. 点击 Header 展开/折叠内嵌子列表；长按 Header 弹出确认框删除该分组全部记录；
/// 3. 展开后的子项复用与扁平列表完全一致的样式，支持点击打开详情、长按删除单条。
@objcMembers
public final class HttpLogGroupCell: UITableViewCell {

    public static let reuseIdentifier = "ShowLog.HttpLogGroupCell"

    private static let timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "HH:mm:ss.SSS"
        return df
    }()

    public var onToggleExpand: ((HttpLogGroupItem) -> Void)?
    public var onGroupLongPressDelete: ((HttpLogGroupItem) -> Void)?
    public var onChildSelect: ((HttpLogRecord) -> Void)?
    public var onChildLongPressDelete: ((HttpLogRecord) -> Void)?

    private let containerCard = UIView()
    private let headerControl = UIControl()
    private let methodLabel = UILabel()
    private let pathLabel = UILabel()
    private let hostLabel = UILabel()
    private let countLabel = UILabel()
    private let latestInfoLabel = UILabel()
    private let expandIndicatorLabel = UILabel()
    private let childrenStack = UIStackView()

    private var currentGroup: HttpLogGroupItem?

    public override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        containerCard.backgroundColor = ShowLogTheme.bgCard
        containerCard.layer.cornerRadius = 8
        containerCard.layer.borderWidth = 1
        containerCard.layer.borderColor = ShowLogTheme.bgCardStroke.cgColor
        containerCard.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(containerCard)

        headerControl.backgroundColor = .clear
        headerControl.translatesAutoresizingMaskIntoConstraints = false
        headerControl.addTarget(self, action: #selector(handleHeaderTap), for: .touchUpInside)
        let headerLongPress = UILongPressGestureRecognizer(target: self, action: #selector(handleHeaderLongPress(_:)))
        headerLongPress.minimumPressDuration = 0.45
        headerControl.addGestureRecognizer(headerLongPress)
        containerCard.addSubview(headerControl)

        methodLabel.font = UIFont.systemFont(ofSize: 12, weight: .bold)
        methodLabel.textColor = ShowLogTheme.textMethod
        methodLabel.setContentHuggingPriority(.required, for: .horizontal)
        methodLabel.translatesAutoresizingMaskIntoConstraints = false

        pathLabel.font = ShowLogTheme.monospacedFont(size: 13, weight: .bold)
        pathLabel.textColor = ShowLogTheme.textPrimary
        pathLabel.numberOfLines = 0
        pathLabel.lineBreakMode = .byCharWrapping
        pathLabel.translatesAutoresizingMaskIntoConstraints = false

        expandIndicatorLabel.font = UIFont.systemFont(ofSize: 12, weight: .bold)
        expandIndicatorLabel.textColor = ShowLogTheme.textSecondary
        expandIndicatorLabel.setContentHuggingPriority(.required, for: .horizontal)
        expandIndicatorLabel.translatesAutoresizingMaskIntoConstraints = false

        hostLabel.font = UIFont.systemFont(ofSize: 11, weight: .regular)
        hostLabel.textColor = ShowLogTheme.textTertiary
        hostLabel.lineBreakMode = .byTruncatingTail
        hostLabel.translatesAutoresizingMaskIntoConstraints = false

        countLabel.font = UIFont.systemFont(ofSize: 11, weight: .semibold)
        countLabel.textColor = ShowLogTheme.actionBtn
        countLabel.setContentHuggingPriority(.required, for: .horizontal)
        countLabel.translatesAutoresizingMaskIntoConstraints = false

        latestInfoLabel.font = ShowLogTheme.monospacedFont(size: 11, weight: .medium)
        latestInfoLabel.textAlignment = .right
        latestInfoLabel.translatesAutoresizingMaskIntoConstraints = false

        headerControl.addSubview(methodLabel)
        headerControl.addSubview(pathLabel)
        headerControl.addSubview(expandIndicatorLabel)
        headerControl.addSubview(hostLabel)
        headerControl.addSubview(countLabel)
        headerControl.addSubview(latestInfoLabel)

        childrenStack.axis = .vertical
        childrenStack.spacing = 6
        childrenStack.translatesAutoresizingMaskIntoConstraints = false
        containerCard.addSubview(childrenStack)

        NSLayoutConstraint.activate([
            containerCard.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            containerCard.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            containerCard.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            containerCard.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),

            headerControl.topAnchor.constraint(equalTo: containerCard.topAnchor),
            headerControl.leadingAnchor.constraint(equalTo: containerCard.leadingAnchor),
            headerControl.trailingAnchor.constraint(equalTo: containerCard.trailingAnchor),

            methodLabel.topAnchor.constraint(equalTo: headerControl.topAnchor, constant: 10),
            methodLabel.leadingAnchor.constraint(equalTo: headerControl.leadingAnchor, constant: 10),

            pathLabel.topAnchor.constraint(equalTo: headerControl.topAnchor, constant: 9),
            pathLabel.leadingAnchor.constraint(equalTo: methodLabel.trailingAnchor, constant: 8),
            pathLabel.trailingAnchor.constraint(equalTo: expandIndicatorLabel.leadingAnchor, constant: -8),

            expandIndicatorLabel.topAnchor.constraint(equalTo: headerControl.topAnchor, constant: 10),
            expandIndicatorLabel.trailingAnchor.constraint(equalTo: headerControl.trailingAnchor, constant: -10),

            hostLabel.topAnchor.constraint(equalTo: pathLabel.bottomAnchor, constant: 5),
            hostLabel.leadingAnchor.constraint(equalTo: headerControl.leadingAnchor, constant: 10),
            hostLabel.trailingAnchor.constraint(equalTo: headerControl.trailingAnchor, constant: -10),

            countLabel.topAnchor.constraint(equalTo: hostLabel.bottomAnchor, constant: 5),
            countLabel.leadingAnchor.constraint(equalTo: headerControl.leadingAnchor, constant: 10),
            countLabel.bottomAnchor.constraint(equalTo: headerControl.bottomAnchor, constant: -9),

            latestInfoLabel.centerYAnchor.constraint(equalTo: countLabel.centerYAnchor),
            latestInfoLabel.leadingAnchor.constraint(greaterThanOrEqualTo: countLabel.trailingAnchor, constant: 8),
            latestInfoLabel.trailingAnchor.constraint(equalTo: headerControl.trailingAnchor, constant: -10),

            childrenStack.topAnchor.constraint(equalTo: headerControl.bottomAnchor),
            childrenStack.leadingAnchor.constraint(equalTo: containerCard.leadingAnchor, constant: 8),
            childrenStack.trailingAnchor.constraint(equalTo: containerCard.trailingAnchor, constant: -8),
            childrenStack.bottomAnchor.constraint(equalTo: containerCard.bottomAnchor, constant: -6)
        ])
    }

    public func configure(with group: HttpLogGroupItem) {
        self.currentGroup = group

        methodLabel.text = group.method
        pathLabel.text = group.path.isEmpty ? "/" : group.path
        hostLabel.text = group.host.isEmpty ? "unknown" : group.host
        countLabel.text = "共 \(group.totalCount) 次调用"
        let statusStr = group.latestStatusCode < 0 ? "FAIL" : "\(group.latestStatusCode)"
        latestInfoLabel.text = "最新: \(statusStr) · \(group.latestDurationMs)ms"
        latestInfoLabel.textColor = group.latestSuccess ? ShowLogTheme.textSecondary : ShowLogTheme.status5xx
        expandIndicatorLabel.text = group.isExpanded ? "▲" : "▼"

        childrenStack.arrangedSubviews.forEach {
            childrenStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        if group.isExpanded {
            childrenStack.isHidden = false
            for record in group.records {
                let row = buildChildRow(for: record)
                childrenStack.addArrangedSubview(row)
            }
        } else {
            childrenStack.isHidden = true
        }
    }

    private func buildChildRow(for record: HttpLogRecord) -> UIView {
        let row = ChildRecordRowView(record: record)
        row.onTap = { [weak self] rec in
            self?.onChildSelect?(rec)
        }
        row.onLongPress = { [weak self] rec in
            self?.onChildLongPressDelete?(rec)
        }
        return row
    }

    @objc private func handleHeaderTap() {
        guard let group = currentGroup else { return }
        onToggleExpand?(group)
    }

    @objc private func handleHeaderLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let group = currentGroup else { return }
        onGroupLongPressDelete?(group)
    }
}

/// 分组展开后的内嵌单条日志卡片视图（与 `HttpLogFlatCell` 视觉保持 1:1 一致）。
private final class ChildRecordRowView: UIView {
    private static let timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "HH:mm:ss.SSS"
        return df
    }()

    let record: HttpLogRecord
    var onTap: ((HttpLogRecord) -> Void)?
    var onLongPress: ((HttpLogRecord) -> Void)?

    init(record: HttpLogRecord) {
        self.record = record
        super.init(frame: .zero)
        backgroundColor = ShowLogTheme.bgPrimary
        layer.cornerRadius = 6
        layer.borderWidth = 1
        layer.borderColor = ShowLogTheme.bgCardStroke.cgColor

        let statusLabel = UILabel()
        statusLabel.font = UIFont.systemFont(ofSize: 11, weight: .bold)
        statusLabel.text = record.success ? "成功" : "失败"
        statusLabel.textColor = record.success ? ShowLogTheme.status2xx : ShowLogTheme.status5xx
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        let methodLabel = UILabel()
        methodLabel.font = UIFont.systemFont(ofSize: 11, weight: .bold)
        methodLabel.textColor = ShowLogTheme.textMethod
        methodLabel.text = record.method
        methodLabel.translatesAutoresizingMaskIntoConstraints = false

        let timeLabel = UILabel()
        timeLabel.font = ShowLogTheme.monospacedFont(size: 11, weight: .regular)
        timeLabel.textColor = ShowLogTheme.textSecondary
        let date = Date(timeIntervalSince1970: TimeInterval(record.timestamp) / 1000.0)
        timeLabel.text = Self.timeFormatter.string(from: date)
        timeLabel.translatesAutoresizingMaskIntoConstraints = false

        let urlLabel = UILabel()
        urlLabel.font = ShowLogTheme.monospacedFont(size: 11.5, weight: .regular)
        urlLabel.textColor = ShowLogTheme.textPrimary
        urlLabel.numberOfLines = 0
        urlLabel.lineBreakMode = .byCharWrapping
        let rawUrl = record.url.trimmingCharacters(in: .whitespacesAndNewlines)
        urlLabel.text = !rawUrl.isEmpty ? rawUrl : ((record.host + record.path).isEmpty ? "/" : (record.host + record.path))
        urlLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(statusLabel)
        addSubview(methodLabel)
        addSubview(timeLabel)
        addSubview(urlLabel)

        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            statusLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),

            methodLabel.centerYAnchor.constraint(equalTo: statusLabel.centerYAnchor),
            methodLabel.leadingAnchor.constraint(equalTo: statusLabel.trailingAnchor, constant: 6),

            timeLabel.centerYAnchor.constraint(equalTo: statusLabel.centerYAnchor),
            timeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),

            urlLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 4),
            urlLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            urlLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            urlLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)

        let lp = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        lp.minimumPressDuration = 0.45
        addGestureRecognizer(lp)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func handleTap() {
        onTap?(record)
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        onLongPress?(record)
    }
}
#endif

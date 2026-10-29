import Foundation
#if canImport(UIKit)
import UIKit

/// 扁平瀑布流网络日志卡片 Cell（严格对齐 Android `HttpLogFlatAdapter.java`）。
/// 为什么这样做：
/// 1. 顶部展示「业务成功/失败徽标 + 请求方式 Method + 精确到毫秒的时间戳 `HH:mm:ss.SSS`」；
/// 2. 下方展示完整请求 URL，`numberOfLines = 0` 不限制行数自动换行，长 URL 也能一目了然；
/// 3. 支持单击查看详情与长按删除单条记录。
@objcMembers
public final class HttpLogFlatCell: UITableViewCell {

    public static let reuseIdentifier = "ShowLog.HttpLogFlatCell"

    private static let timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "HH:mm:ss.SSS"
        return df
    }()

    public var onLongPressDelete: ((HttpLogRecord) -> Void)?

    private let cardView = UIView()
    private let statusBadgeView = UIView()
    private let statusLabel = UILabel()
    private let methodLabel = UILabel()
    private let durationLabel = UILabel()
    private let timeLabel = UILabel()
    private let urlLabel = UILabel()
    private var currentRecord: HttpLogRecord?

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

        cardView.backgroundColor = ShowLogTheme.bgCard
        cardView.layer.cornerRadius = 8
        cardView.layer.borderWidth = 1
        cardView.layer.borderColor = ShowLogTheme.bgCardStroke.cgColor
        cardView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(cardView)

        statusBadgeView.layer.cornerRadius = 4
        statusBadgeView.clipsToBounds = true
        statusBadgeView.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = UIFont.systemFont(ofSize: 10, weight: .bold)
        statusLabel.textAlignment = .center
        statusLabel.setContentHuggingPriority(.required, for: .horizontal)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusBadgeView.addSubview(statusLabel)

        methodLabel.font = UIFont.systemFont(ofSize: 12, weight: .heavy)
        methodLabel.textColor = ShowLogTheme.textMethod
        methodLabel.setContentHuggingPriority(.required, for: .horizontal)
        methodLabel.translatesAutoresizingMaskIntoConstraints = false

        durationLabel.font = ShowLogTheme.monospacedFont(size: 11, weight: .medium)
        durationLabel.textColor = ShowLogTheme.textSecondary
        durationLabel.translatesAutoresizingMaskIntoConstraints = false

        timeLabel.font = ShowLogTheme.monospacedFont(size: 11, weight: .regular)
        timeLabel.textColor = ShowLogTheme.textSecondary
        timeLabel.textAlignment = .right
        timeLabel.translatesAutoresizingMaskIntoConstraints = false

        urlLabel.font = ShowLogTheme.monospacedFont(size: 12, weight: .regular)
        urlLabel.textColor = ShowLogTheme.textPrimary
        urlLabel.numberOfLines = 0
        urlLabel.lineBreakMode = .byCharWrapping
        urlLabel.translatesAutoresizingMaskIntoConstraints = false

        cardView.addSubview(statusBadgeView)
        cardView.addSubview(methodLabel)
        cardView.addSubview(durationLabel)
        cardView.addSubview(timeLabel)
        cardView.addSubview(urlLabel)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),

            statusBadgeView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 8),
            statusBadgeView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 10),
            statusBadgeView.heightAnchor.constraint(equalToConstant: 18),

            statusLabel.topAnchor.constraint(equalTo: statusBadgeView.topAnchor, constant: 1),
            statusLabel.bottomAnchor.constraint(equalTo: statusBadgeView.bottomAnchor, constant: -1),
            statusLabel.leadingAnchor.constraint(equalTo: statusBadgeView.leadingAnchor, constant: 5),
            statusLabel.trailingAnchor.constraint(equalTo: statusBadgeView.trailingAnchor, constant: -5),

            methodLabel.centerYAnchor.constraint(equalTo: statusBadgeView.centerYAnchor),
            methodLabel.leadingAnchor.constraint(equalTo: statusBadgeView.trailingAnchor, constant: 8),

            timeLabel.centerYAnchor.constraint(equalTo: statusBadgeView.centerYAnchor),
            timeLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -10),

            durationLabel.centerYAnchor.constraint(equalTo: statusBadgeView.centerYAnchor),
            durationLabel.trailingAnchor.constraint(equalTo: timeLabel.leadingAnchor, constant: -8),
            durationLabel.leadingAnchor.constraint(greaterThanOrEqualTo: methodLabel.trailingAnchor, constant: 6),

            urlLabel.topAnchor.constraint(equalTo: statusBadgeView.bottomAnchor, constant: 6),
            urlLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 10),
            urlLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -10),
            urlLabel.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -8)
        ])

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.45
        cardView.addGestureRecognizer(longPress)
    }

    public func configure(with record: HttpLogRecord, isChildItem: Bool = false) {
        self.currentRecord = record
        cardView.backgroundColor = isChildItem ? ShowLogTheme.bgPrimary : ShowLogTheme.bgCard

        if record.success {
            statusBadgeView.backgroundColor = ShowLogTheme.color(hex: 0x064E3B, alpha: 0.65)
            statusLabel.textColor = ShowLogTheme.status2xx
            let codeText = record.statusCode > 0 ? "\(record.statusCode)" : "OK"
            statusLabel.text = codeText
        } else {
            statusBadgeView.backgroundColor = ShowLogTheme.color(hex: 0x7F1D1D, alpha: 0.65)
            statusLabel.textColor = ShowLogTheme.status5xx
            let codeText = record.statusCode > 0 ? "\(record.statusCode)" : "ERR"
            statusLabel.text = codeText
        }

        methodLabel.text = record.method
        durationLabel.text = "\(record.durationMs)ms"

        let date = Date(timeIntervalSince1970: TimeInterval(record.timestamp) / 1000.0)
        timeLabel.text = Self.timeFormatter.string(from: date)

        let rawUrl = record.url.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rawUrl.isEmpty {
            urlLabel.text = rawUrl
        } else {
            let fallback = record.host + record.path
            urlLabel.text = fallback.isEmpty ? "/" : fallback
        }
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let record = currentRecord else { return }
        onLongPressDelete?(record)
    }
}
#endif

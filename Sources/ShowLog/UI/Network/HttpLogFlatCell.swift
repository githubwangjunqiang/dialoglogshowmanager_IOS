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
    private let statusLabel = UILabel()
    private let methodLabel = UILabel()
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

        statusLabel.font = UIFont.systemFont(ofSize: 11, weight: .bold)
        statusLabel.setContentHuggingPriority(.required, for: .horizontal)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        methodLabel.font = UIFont.systemFont(ofSize: 12, weight: .bold)
        methodLabel.textColor = ShowLogTheme.textMethod
        methodLabel.setContentHuggingPriority(.required, for: .horizontal)
        methodLabel.translatesAutoresizingMaskIntoConstraints = false

        timeLabel.font = ShowLogTheme.monospacedFont(size: 11, weight: .regular)
        timeLabel.textColor = ShowLogTheme.textSecondary
        timeLabel.textAlignment = .right
        timeLabel.translatesAutoresizingMaskIntoConstraints = false

        urlLabel.font = ShowLogTheme.monospacedFont(size: 12, weight: .regular)
        urlLabel.textColor = ShowLogTheme.textPrimary
        urlLabel.numberOfLines = 0
        urlLabel.lineBreakMode = .byCharWrapping
        urlLabel.translatesAutoresizingMaskIntoConstraints = false

        cardView.addSubview(statusLabel)
        cardView.addSubview(methodLabel)
        cardView.addSubview(timeLabel)
        cardView.addSubview(urlLabel)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),

            statusLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 8),
            statusLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 10),

            methodLabel.centerYAnchor.constraint(equalTo: statusLabel.centerYAnchor),
            methodLabel.leadingAnchor.constraint(equalTo: statusLabel.trailingAnchor, constant: 8),

            timeLabel.centerYAnchor.constraint(equalTo: statusLabel.centerYAnchor),
            timeLabel.leadingAnchor.constraint(greaterThanOrEqualTo: methodLabel.trailingAnchor, constant: 8),
            timeLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -10),

            urlLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 6),
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

        statusLabel.text = record.success ? "成功" : "失败"
        statusLabel.textColor = record.success ? ShowLogTheme.status2xx : ShowLogTheme.status5xx

        methodLabel.text = record.method
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

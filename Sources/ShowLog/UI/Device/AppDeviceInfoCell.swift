import Foundation
#if canImport(UIKit)
import UIKit

/// 设备与应用全景指标条目 Cell（对齐 Android `AppDeviceInfoAdapter.ViewHolder`）。
@objcMembers
public final class AppDeviceInfoCell: UITableViewCell {

    public static let reuseIdentifier = "ShowLog.AppDeviceInfoCell"

    private let cardView = UIView()
    private let keyLabel = UILabel()
    private let categoryBadgeLabel = UILabel()
    private let valueLabel = UILabel()

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

        keyLabel.font = UIFont.systemFont(ofSize: 12.5, weight: .semibold)
        keyLabel.textColor = ShowLogTheme.textPrimary
        keyLabel.translatesAutoresizingMaskIntoConstraints = false

        categoryBadgeLabel.font = UIFont.systemFont(ofSize: 10, weight: .medium)
        categoryBadgeLabel.textColor = ShowLogTheme.textSecondary
        categoryBadgeLabel.backgroundColor = ShowLogTheme.bgPill
        categoryBadgeLabel.layer.cornerRadius = 4
        categoryBadgeLabel.clipsToBounds = true
        categoryBadgeLabel.textAlignment = .center
        categoryBadgeLabel.setContentHuggingPriority(.required, for: .horizontal)
        categoryBadgeLabel.translatesAutoresizingMaskIntoConstraints = false

        valueLabel.font = ShowLogTheme.monospacedFont(size: 12, weight: .medium)
        valueLabel.numberOfLines = 0
        valueLabel.lineBreakMode = .byCharWrapping
        valueLabel.translatesAutoresizingMaskIntoConstraints = false

        cardView.addSubview(keyLabel)
        cardView.addSubview(categoryBadgeLabel)
        cardView.addSubview(valueLabel)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 3),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -3),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),

            keyLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 8),
            keyLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 10),
            keyLabel.trailingAnchor.constraint(lessThanOrEqualTo: categoryBadgeLabel.leadingAnchor, constant: -8),

            categoryBadgeLabel.centerYAnchor.constraint(equalTo: keyLabel.centerYAnchor),
            categoryBadgeLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -10),
            categoryBadgeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 52),
            categoryBadgeLabel.heightAnchor.constraint(equalToConstant: 18),

            valueLabel.topAnchor.constraint(equalTo: keyLabel.bottomAnchor, constant: 5),
            valueLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 10),
            valueLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -10),
            valueLabel.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -8)
        ])
    }

    public func configure(with item: AppDeviceInfo.InfoItem) {
        keyLabel.text = item.key
        categoryBadgeLabel.text = " \(item.category) "
        valueLabel.text = item.value

        if item.value.contains("⚠️") || item.value.contains("🔥") {
            valueLabel.textColor = ShowLogTheme.statusError
        } else if item.isImportant {
            valueLabel.textColor = ShowLogTheme.status2xx
        } else {
            valueLabel.textColor = ShowLogTheme.actionBtn
        }
    }
}
#endif

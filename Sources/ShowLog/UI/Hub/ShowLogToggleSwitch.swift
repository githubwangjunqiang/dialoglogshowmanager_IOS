import Foundation
#if canImport(UIKit)
import UIKit

/// 两态滑动胶囊开关（1:1 复刻 Android `ShowLogToggleSwitch.java`，160ms 平滑滑块动画）。
/// 用于网络控制台的「列表 / 分组」与「倒序 / 正序」切换。
@objcMembers
public final class ShowLogToggleSwitch: UIView {

    public static let thumbAnimDuration: TimeInterval = 0.16

    public var onCheckedChanged: ((Bool) -> Void)?

    private let thumbView = UIView()
    private let leftLabel = UILabel()
    private let rightLabel = UILabel()

    private(set) public var isChecked: Bool = false
    private let insetPadding: CGFloat = 2.0

    public override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        backgroundColor = ShowLogTheme.bgPill
        layer.cornerRadius = 6
        layer.borderWidth = 1
        layer.borderColor = ShowLogTheme.bgCardStroke.cgColor
        clipsToBounds = true

        thumbView.backgroundColor = ShowLogTheme.bgPillSelected
        thumbView.layer.cornerRadius = 4
        addSubview(thumbView)

        leftLabel.textAlignment = .center
        leftLabel.font = UIFont.systemFont(ofSize: 11, weight: .bold)
        leftLabel.isUserInteractionEnabled = true
        addSubview(leftLabel)

        rightLabel.textAlignment = .center
        rightLabel.font = UIFont.systemFont(ofSize: 11, weight: .regular)
        rightLabel.isUserInteractionEnabled = true
        addSubview(rightLabel)

        let leftTap = UITapGestureRecognizer(target: self, action: #selector(onLeftTapped))
        leftLabel.addGestureRecognizer(leftTap)

        let rightTap = UITapGestureRecognizer(target: self, action: #selector(onRightTapped))
        rightLabel.addGestureRecognizer(rightTap)

        updateLabelStyles()
    }

    public func setLabels(left: String, right: String) {
        leftLabel.text = left
        rightLabel.text = right
    }

    /// 设置当前选中状态（只更新视觉，不触发 `onCheckedChanged` 回调）。
    public func setChecked(_ checked: Bool, animated: Bool) {
        let changed = (isChecked != checked)
        isChecked = checked
        updateLabelStyles()
        if animated && changed && bounds.width > 0 {
            UIView.animate(withDuration: Self.thumbAnimDuration, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
                self.updateFrames()
            }
        } else {
            updateFrames()
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        updateFrames()
    }

    private func updateFrames() {
        let w = bounds.width
        let h = bounds.height
        guard w > insetPadding * 2, h > insetPadding * 2 else { return }

        let contentW = w - insetPadding * 2
        let contentH = h - insetPadding * 2
        let halfW = contentW / 2.0

        leftLabel.frame = CGRect(x: insetPadding, y: insetPadding, width: halfW, height: contentH)
        rightLabel.frame = CGRect(x: insetPadding + halfW, y: insetPadding, width: halfW, height: contentH)

        let thumbX = isChecked ? (insetPadding + halfW) : insetPadding
        thumbView.frame = CGRect(x: thumbX, y: insetPadding, width: halfW, height: contentH)
    }

    private func updateLabelStyles() {
        leftLabel.textColor = isChecked ? ShowLogTheme.textSecondary : ShowLogTheme.textOnAccent
        rightLabel.textColor = isChecked ? ShowLogTheme.textOnAccent : ShowLogTheme.textSecondary
        leftLabel.font = UIFont.systemFont(ofSize: 11, weight: isChecked ? .regular : .bold)
        rightLabel.font = UIFont.systemFont(ofSize: 11, weight: isChecked ? .bold : .regular)
    }

    @objc private func onLeftTapped() {
        setCheckedFromUser(false)
    }

    @objc private func onRightTapped() {
        setCheckedFromUser(true)
    }

    private func setCheckedFromUser(_ checked: Bool) {
        guard isChecked != checked else { return }
        setChecked(checked, animated: true)
        onCheckedChanged?(checked)
    }
}
#endif

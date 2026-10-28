import Foundation
#if canImport(UIKit)
import UIKit

/// 独立关键词搜索弹框（对齐 Android `SearchKeywordDialog.java`，带防软键盘遮挡上移保护）。
@objcMembers
public final class SearchKeywordAlertView: UIView, UITextFieldDelegate {

    private let cardView = UIView()
    private let textField = UITextField()
    private var centerYConstraint: NSLayoutConstraint?
    private var actionDispatched = false

    private let onConfirm: (String) -> Void
    private let onClear: () -> Void
    private let onCancel: () -> Void

    public init(
        initialKeyword: String,
        onConfirm: @escaping (String) -> Void,
        onClear: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.onConfirm = onConfirm
        self.onClear = onClear
        self.onCancel = onCancel
        super.init(frame: .zero)
        setupViews(initialKeyword: initialKeyword)
        registerKeyboardNotifications()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    public static func show(
        in parentView: UIView,
        initialKeyword: String,
        onConfirm: @escaping (String) -> Void,
        onClear: @escaping () -> Void,
        onCancel: @escaping () -> Void = {}
    ) {
        let alert = SearchKeywordAlertView(
            initialKeyword: initialKeyword,
            onConfirm: onConfirm,
            onClear: onClear,
            onCancel: onCancel
        )
        alert.translatesAutoresizingMaskIntoConstraints = false
        parentView.addSubview(alert)
        NSLayoutConstraint.activate([
            alert.topAnchor.constraint(equalTo: parentView.topAnchor),
            alert.bottomAnchor.constraint(equalTo: parentView.bottomAnchor),
            alert.leadingAnchor.constraint(equalTo: parentView.leadingAnchor),
            alert.trailingAnchor.constraint(equalTo: parentView.trailingAnchor)
        ])
        alert.presentAnimated()
    }

    private func setupViews(initialKeyword: String) {
        backgroundColor = UIColor.black.withAlphaComponent(0.62)
        if #available(iOS 13.0, *) {
            overrideUserInterfaceStyle = .dark
        }

        cardView.backgroundColor = ShowLogTheme.bgSurface
        cardView.layer.cornerRadius = 12
        cardView.layer.borderWidth = 1
        cardView.layer.borderColor = ShowLogTheme.bgCardStroke.cgColor
        cardView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(cardView)

        let titleLabel = UILabel()
        titleLabel.text = "🔍 搜索网络日志"
        titleLabel.font = UIFont.systemFont(ofSize: 15, weight: .bold)
        titleLabel.textColor = ShowLogTheme.textPrimary
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let subtitleLabel = UILabel()
        subtitleLabel.text = "支持匹配 URL、域名 Host、路径 Path、状态码或业务提示信息"
        subtitleLabel.font = UIFont.systemFont(ofSize: 12, weight: .regular)
        subtitleLabel.textColor = ShowLogTheme.textSecondary
        subtitleLabel.numberOfLines = 2
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        textField.text = initialKeyword
        textField.font = ShowLogTheme.monospacedFont(size: 13)
        textField.textColor = ShowLogTheme.textPrimary
        textField.backgroundColor = ShowLogTheme.bgPrimary
        textField.layer.cornerRadius = 8
        textField.layer.borderWidth = 1
        textField.layer.borderColor = ShowLogTheme.bgCardStroke.cgColor
        textField.returnKeyType = .done
        textField.clearButtonMode = .whileEditing
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.delegate = self
        textField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 1))
        textField.leftViewMode = .always
        textField.attributedPlaceholder = NSAttributedString(
            string: "输入接口路径、域名或状态码...",
            attributes: [.foregroundColor: ShowLogTheme.textTertiary]
        )
        textField.translatesAutoresizingMaskIntoConstraints = false

        let btnCancel = buildButton(title: "取消", bgColor: ShowLogTheme.bgPill, textColor: ShowLogTheme.textSecondary)
        btnCancel.addTarget(self, action: #selector(handleCancel), for: .touchUpInside)

        let btnClear = buildButton(title: "清除筛选", bgColor: ShowLogTheme.bgPill, textColor: ShowLogTheme.status4xx)
        btnClear.addTarget(self, action: #selector(handleClear), for: .touchUpInside)

        let btnConfirm = buildButton(title: "确定搜索", bgColor: ShowLogTheme.bgPillSelected, textColor: ShowLogTheme.textOnAccent)
        btnConfirm.addTarget(self, action: #selector(handleConfirm), for: .touchUpInside)

        let buttonStack = UIStackView(arrangedSubviews: [btnCancel, btnClear, btnConfirm])
        buttonStack.axis = .horizontal
        buttonStack.distribution = .fillEqually
        buttonStack.spacing = 8
        buttonStack.translatesAutoresizingMaskIntoConstraints = false

        cardView.addSubview(titleLabel)
        cardView.addSubview(subtitleLabel)
        cardView.addSubview(textField)
        cardView.addSubview(buttonStack)

        let cy = cardView.centerYAnchor.constraint(equalTo: centerYAnchor)
        self.centerYConstraint = cy

        NSLayoutConstraint.activate([
            cardView.centerXAnchor.constraint(equalTo: centerXAnchor),
            cy,
            cardView.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.88),

            titleLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            subtitleLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),

            textField.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 12),
            textField.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            textField.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),
            textField.heightAnchor.constraint(equalToConstant: 38),

            buttonStack.topAnchor.constraint(equalTo: textField.bottomAnchor, constant: 14),
            buttonStack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            buttonStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),
            buttonStack.heightAnchor.constraint(equalToConstant: 36),
            buttonStack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -16)
        ])
    }

    private func buildButton(title: String, bgColor: UIColor, textColor: UIColor) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle(title, for: .normal)
        btn.setTitleColor(textColor, for: .normal)
        btn.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .bold)
        btn.backgroundColor = bgColor
        btn.layer.cornerRadius = 6
        return btn
    }

    private func presentAnimated() {
        alpha = 0
        UIView.animate(withDuration: 0.18) {
            self.alpha = 1
        } completion: { _ in
            self.textField.becomeFirstResponder()
        }
    }

    private func dismissAnimated(completion: @escaping () -> Void) {
        textField.resignFirstResponder()
        UIView.animate(withDuration: 0.15, animations: {
            self.alpha = 0
        }, completion: { _ in
            self.removeFromSuperview()
            completion()
        })
    }

    @objc private func handleConfirm() {
        guard !actionDispatched else { return }
        actionDispatched = true
        let kw = (textField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        dismissAnimated { [onConfirm] in
            onConfirm(kw)
        }
    }

    @objc private func handleClear() {
        guard !actionDispatched else { return }
        actionDispatched = true
        dismissAnimated { [onClear] in
            onClear()
        }
    }

    @objc private func handleCancel() {
        guard !actionDispatched else { return }
        actionDispatched = true
        dismissAnimated { [onCancel] in
            onCancel()
        }
    }

    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        handleConfirm()
        return true
    }

    private func registerKeyboardNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onKeyboardWillChange(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onKeyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    @objc private func onKeyboardWillChange(_ notification: Notification) {
        guard let frameValue = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue else {
            return
        }
        let kbHeight = frameValue.cgRectValue.height
        centerYConstraint?.constant = -min(110, kbHeight * 0.32)
        UIView.animate(withDuration: 0.22) {
            self.layoutIfNeeded()
        }
    }

    @objc private func onKeyboardWillHide(_ notification: Notification) {
        centerYConstraint?.constant = 0
        UIView.animate(withDuration: 0.22) {
            self.layoutIfNeeded()
        }
    }
}
#endif

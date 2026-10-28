import Foundation
#if canImport(UIKit)
import UIKit

/// 网络日志详情弹框控制器（严格对齐 Android `HttpLogDetailDialog.java`）。
/// 为什么这样做：
/// 1. 宽高为屏幕 `95% × 88%`，支持 Overview / Request / Response / Error 四级子 Tab 切换；
/// 2. 顶部提供一键复制 URL 与标准 cURL 命令（自动转义请求头与请求体）；
/// 3. 底部提供一键复制当前 Tab 报文内容与系统分享。
@objcMembers
public final class HttpLogDetailViewController: UIViewController {

    private static let TAB_OVERVIEW = 0
    private static let TAB_REQUEST = 1
    private static let TAB_RESPONSE = 2
    private static let TAB_ERROR = 3

    private static let dateTimeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return df
    }()

    public let record: HttpLogRecord
    private var currentTab: Int = TAB_OVERVIEW
    private let throttler = ClickThrottler(intervalMs: ShowLogTheme.throttleMs)

    private let dialogCard = UIView()
    private let statusLabel = UILabel()
    private let methodLabel = UILabel()
    private let urlLabel = UILabel()

    private let tabOverviewBtn = UIButton(type: .custom)
    private let tabRequestBtn = UIButton(type: .custom)
    private let tabResponseBtn = UIButton(type: .custom)
    private let tabErrorBtn = UIButton(type: .custom)

    private let contentTextView = UITextView()

    public init(record: HttpLogRecord) {
        self.record = record
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
        bindRecord()
    }

    private func setupUI() {
        dialogCard.backgroundColor = ShowLogTheme.bgSurface
        dialogCard.layer.cornerRadius = 12
        dialogCard.layer.borderWidth = 1
        dialogCard.layer.borderColor = ShowLogTheme.bgCardStroke.cgColor
        dialogCard.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dialogCard)

        let headerTitle = UILabel()
        headerTitle.text = "🌐 网络报文详情 (Detail)"
        headerTitle.font = UIFont.systemFont(ofSize: 15, weight: .bold)
        headerTitle.textColor = ShowLogTheme.textPrimary
        headerTitle.translatesAutoresizingMaskIntoConstraints = false

        let closeBtn = UIButton(type: .custom)
        closeBtn.setTitle("✕", for: .normal)
        closeBtn.setTitleColor(ShowLogTheme.textPrimary, for: .normal)
        closeBtn.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .bold)
        closeBtn.backgroundColor = ShowLogTheme.statusError
        closeBtn.layer.cornerRadius = 6
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        closeBtn.addTarget(self, action: #selector(handleClose), for: .touchUpInside)

        let summaryBox = UIView()
        summaryBox.backgroundColor = ShowLogTheme.bgCard
        summaryBox.layer.cornerRadius = 8
        summaryBox.layer.borderWidth = 1
        summaryBox.layer.borderColor = ShowLogTheme.bgCardStroke.cgColor
        summaryBox.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = UIFont.systemFont(ofSize: 12, weight: .bold)
        statusLabel.setContentHuggingPriority(.required, for: .horizontal)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        methodLabel.font = UIFont.systemFont(ofSize: 12, weight: .bold)
        methodLabel.textColor = ShowLogTheme.textMethod
        methodLabel.setContentHuggingPriority(.required, for: .horizontal)
        methodLabel.translatesAutoresizingMaskIntoConstraints = false

        let copyUrlBtn = buildActionButton(title: "复制 URL", bgColor: ShowLogTheme.bgPill, textColor: ShowLogTheme.actionBtn)
        copyUrlBtn.addTarget(self, action: #selector(handleCopyUrl), for: .touchUpInside)

        let copyCurlBtn = buildActionButton(title: "复制 cURL", bgColor: ShowLogTheme.bgPill, textColor: ShowLogTheme.actionBtn)
        copyCurlBtn.addTarget(self, action: #selector(handleCopyCurl), for: .touchUpInside)

        urlLabel.font = ShowLogTheme.monospacedFont(size: 11.5)
        urlLabel.textColor = ShowLogTheme.textPrimary
        urlLabel.numberOfLines = 3
        urlLabel.lineBreakMode = .byCharWrapping
        urlLabel.translatesAutoresizingMaskIntoConstraints = false

        summaryBox.addSubview(statusLabel)
        summaryBox.addSubview(methodLabel)
        summaryBox.addSubview(copyUrlBtn)
        summaryBox.addSubview(copyCurlBtn)
        summaryBox.addSubview(urlLabel)

        configureSubTabButton(tabOverviewBtn, title: "Overview", tag: Self.TAB_OVERVIEW)
        configureSubTabButton(tabRequestBtn, title: "Request", tag: Self.TAB_REQUEST)
        configureSubTabButton(tabResponseBtn, title: "Response", tag: Self.TAB_RESPONSE)
        configureSubTabButton(tabErrorBtn, title: "Error", tag: Self.TAB_ERROR)

        let tabStack = UIStackView(arrangedSubviews: [tabOverviewBtn, tabRequestBtn, tabResponseBtn, tabErrorBtn])
        tabStack.axis = .horizontal
        tabStack.distribution = .fillEqually
        tabStack.spacing = 6
        tabStack.translatesAutoresizingMaskIntoConstraints = false

        contentTextView.backgroundColor = ShowLogTheme.bgPrimary
        contentTextView.textColor = ShowLogTheme.textPrimary
        contentTextView.font = ShowLogTheme.monospacedFont(size: 12)
        contentTextView.isEditable = false
        contentTextView.isSelectable = true
        contentTextView.layer.cornerRadius = 8
        contentTextView.layer.borderWidth = 1
        contentTextView.layer.borderColor = ShowLogTheme.bgCardStroke.cgColor
        contentTextView.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        contentTextView.translatesAutoresizingMaskIntoConstraints = false

        let copyTabBtn = buildActionButton(title: "📋 复制当前页内容", bgColor: ShowLogTheme.bgPillSelected, textColor: ShowLogTheme.textOnAccent)
        copyTabBtn.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .bold)
        copyTabBtn.addTarget(self, action: #selector(handleCopyCurrentTab), for: .touchUpInside)

        let shareBtn = buildActionButton(title: "📤 分享报文", bgColor: ShowLogTheme.bgPill, textColor: ShowLogTheme.textPrimary)
        shareBtn.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .bold)
        shareBtn.addTarget(self, action: #selector(handleShareContent(_:)), for: .touchUpInside)

        let bottomStack = UIStackView(arrangedSubviews: [copyTabBtn, shareBtn])
        bottomStack.axis = .horizontal
        bottomStack.distribution = .fillEqually
        bottomStack.spacing = 10
        bottomStack.translatesAutoresizingMaskIntoConstraints = false

        dialogCard.addSubview(headerTitle)
        dialogCard.addSubview(closeBtn)
        dialogCard.addSubview(summaryBox)
        dialogCard.addSubview(tabStack)
        dialogCard.addSubview(contentTextView)
        dialogCard.addSubview(bottomStack)

        NSLayoutConstraint.activate([
            dialogCard.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            dialogCard.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            dialogCard.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.95),
            dialogCard.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.88),

            headerTitle.topAnchor.constraint(equalTo: dialogCard.topAnchor, constant: 12),
            headerTitle.leadingAnchor.constraint(equalTo: dialogCard.leadingAnchor, constant: 12),

            closeBtn.centerYAnchor.constraint(equalTo: headerTitle.centerYAnchor),
            closeBtn.trailingAnchor.constraint(equalTo: dialogCard.trailingAnchor, constant: -12),
            closeBtn.widthAnchor.constraint(equalToConstant: 32),
            closeBtn.heightAnchor.constraint(equalToConstant: 28),

            summaryBox.topAnchor.constraint(equalTo: headerTitle.bottomAnchor, constant: 10),
            summaryBox.leadingAnchor.constraint(equalTo: dialogCard.leadingAnchor, constant: 10),
            summaryBox.trailingAnchor.constraint(equalTo: dialogCard.trailingAnchor, constant: -10),

            statusLabel.topAnchor.constraint(equalTo: summaryBox.topAnchor, constant: 8),
            statusLabel.leadingAnchor.constraint(equalTo: summaryBox.leadingAnchor, constant: 10),

            methodLabel.centerYAnchor.constraint(equalTo: statusLabel.centerYAnchor),
            methodLabel.leadingAnchor.constraint(equalTo: statusLabel.trailingAnchor, constant: 8),

            copyCurlBtn.centerYAnchor.constraint(equalTo: statusLabel.centerYAnchor),
            copyCurlBtn.trailingAnchor.constraint(equalTo: summaryBox.trailingAnchor, constant: -8),
            copyCurlBtn.heightAnchor.constraint(equalToConstant: 24),

            copyUrlBtn.centerYAnchor.constraint(equalTo: statusLabel.centerYAnchor),
            copyUrlBtn.trailingAnchor.constraint(equalTo: copyCurlBtn.leadingAnchor, constant: -6),
            copyUrlBtn.heightAnchor.constraint(equalToConstant: 24),

            urlLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 6),
            urlLabel.leadingAnchor.constraint(equalTo: summaryBox.leadingAnchor, constant: 10),
            urlLabel.trailingAnchor.constraint(equalTo: summaryBox.trailingAnchor, constant: -10),
            urlLabel.bottomAnchor.constraint(equalTo: summaryBox.bottomAnchor, constant: -8),

            tabStack.topAnchor.constraint(equalTo: summaryBox.bottomAnchor, constant: 8),
            tabStack.leadingAnchor.constraint(equalTo: dialogCard.leadingAnchor, constant: 10),
            tabStack.trailingAnchor.constraint(equalTo: dialogCard.trailingAnchor, constant: -10),
            tabStack.heightAnchor.constraint(equalToConstant: 32),

            contentTextView.topAnchor.constraint(equalTo: tabStack.bottomAnchor, constant: 8),
            contentTextView.leadingAnchor.constraint(equalTo: dialogCard.leadingAnchor, constant: 10),
            contentTextView.trailingAnchor.constraint(equalTo: dialogCard.trailingAnchor, constant: -10),
            contentTextView.bottomAnchor.constraint(equalTo: bottomStack.topAnchor, constant: -10),

            bottomStack.leadingAnchor.constraint(equalTo: dialogCard.leadingAnchor, constant: 10),
            bottomStack.trailingAnchor.constraint(equalTo: dialogCard.trailingAnchor, constant: -10),
            bottomStack.bottomAnchor.constraint(equalTo: dialogCard.bottomAnchor, constant: -12),
            bottomStack.heightAnchor.constraint(equalToConstant: 38)
        ])
    }

    private func buildActionButton(title: String, bgColor: UIColor, textColor: UIColor) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle(title, for: .normal)
        btn.setTitleColor(textColor, for: .normal)
        btn.titleLabel?.font = UIFont.systemFont(ofSize: 11, weight: .semibold)
        btn.backgroundColor = bgColor
        btn.layer.cornerRadius = 5
        btn.contentEdgeInsets = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }

    private func configureSubTabButton(_ button: UIButton, title: String, tag: Int) {
        button.setTitle(title, for: .normal)
        button.tag = tag
        button.layer.cornerRadius = 6
        button.backgroundColor = ShowLogTheme.bgPill
        button.addTarget(self, action: #selector(onSubTabTapped(_:)), for: .touchUpInside)
    }

    private func bindRecord() {
        methodLabel.text = record.method
        urlLabel.text = record.url

        if !record.success {
            statusLabel.text = record.statusCode < 0 ? "FAIL" : "\(record.statusCode) (FAIL)"
            statusLabel.textColor = ShowLogTheme.statusError
        } else {
            statusLabel.text = "\(record.statusCode)"
            if (200..<300).contains(record.statusCode) {
                statusLabel.textColor = ShowLogTheme.status2xx
            } else if (300..<400).contains(record.statusCode) {
                statusLabel.textColor = ShowLogTheme.status3xx
            } else if (400..<500).contains(record.statusCode) {
                statusLabel.textColor = ShowLogTheme.status4xx
            } else {
                statusLabel.textColor = ShowLogTheme.status5xx
            }
        }

        let hasError = !(record.errorMessage ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !record.success
        tabErrorBtn.isHidden = !hasError

        switchTab(Self.TAB_OVERVIEW)
    }

    @objc private func onSubTabTapped(_ sender: UIButton) {
        switchTab(sender.tag)
    }

    private func switchTab(_ tab: Int) {
        currentTab = tab
        let buttons = [tabOverviewBtn, tabRequestBtn, tabResponseBtn, tabErrorBtn]
        for btn in buttons {
            let isSelected = (btn.tag == tab)
            if btn.tag == Self.TAB_ERROR {
                btn.setTitleColor(ShowLogTheme.statusError, for: .normal)
                btn.backgroundColor = isSelected ? ShowLogTheme.color(hex: 0x3A1A1E) : ShowLogTheme.bgPill
            } else {
                btn.setTitleColor(isSelected ? ShowLogTheme.textPrimary : ShowLogTheme.textTertiary, for: .normal)
                btn.backgroundColor = isSelected ? ShowLogTheme.bgCard : ShowLogTheme.bgPill
            }
            btn.titleLabel?.font = UIFont.systemFont(ofSize: 12, weight: isSelected ? .bold : .regular)
        }

        switch tab {
        case Self.TAB_OVERVIEW:
            contentTextView.text = Self.buildOverviewText(for: record)
        case Self.TAB_REQUEST:
            contentTextView.text = Self.buildRequestText(for: record)
        case Self.TAB_RESPONSE:
            contentTextView.text = Self.buildResponseText(for: record)
        case Self.TAB_ERROR:
            contentTextView.text = Self.buildErrorText(for: record)
        default:
            break
        }
        contentTextView.setContentOffset(.zero, animated: false)
    }

    // MARK: - Text Builders (Aligned with Android HttpLogDetailDialog.java)

    public static func buildOverviewText(for record: HttpLogRecord) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(record.timestamp) / 1000.0)
        let timeStr = dateTimeFormatter.string(from: date)
        var sb = "=== 请求概览 (Overview) ===\n\n"
        sb += "• 完整地址: \(record.url)\n"
        sb += "• 域名 Host: \(record.host)\n"
        sb += "• 接口 Path: \(record.path)\n"
        sb += "• 请求方式: \(record.method)\n"
        sb += "• 业务裁决: \(record.success ? "✅ 成功 (SUCCESS)" : "❌ 失败 (FAILED)")\n"
        sb += "• 业务提示: \(record.message.isEmpty ? "N/A" : record.message)\n"
        sb += "• 传输代码: \(record.statusCode < 0 ? "FAILED (-1)" : "\(record.statusCode)")\n"
        sb += "• 耗时统计: \(record.durationMs) ms\n"
        sb += "• 发起时间: \(timeStr)\n"
        sb += "• 请求体大小: \(record.requestSize) bytes\n"
        sb += "• 响应体大小: \(record.responseSize) bytes\n"
        sb += "• 报文类型: \((record.contentType?.isEmpty == false) ? record.contentType! : "N/A")\n"
        if let err = record.errorMessage, !err.isEmpty {
            sb += "\n⚠️ 异常警告:\n\(err)\n"
        }
        return sb
    }

    public static func buildRequestText(for record: HttpLogRecord) -> String {
        var sb = "=== 请求头 (Request Headers) ===\n\n"
        if let headers = record.requestHeaders?.trimmingCharacters(in: .whitespacesAndNewlines), !headers.isEmpty {
            sb += "\(headers)\n\n"
        } else {
            sb += "(Empty Headers)\n\n"
        }
        sb += "=== 请求体 (Request Body) ===\n\n"
        if let body = record.requestBody?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty {
            sb += JsonFormatter.formatJsonString(body)
        } else {
            sb += "(Empty Body)"
        }
        return sb
    }

    public static func buildResponseText(for record: HttpLogRecord) -> String {
        var sb = "=== 响应头 (Response Headers) ===\n\n"
        if let headers = record.responseHeaders?.trimmingCharacters(in: .whitespacesAndNewlines), !headers.isEmpty {
            sb += "\(headers)\n\n"
        } else {
            sb += "(Empty Headers)\n\n"
        }
        sb += "=== 响应体 (Response Body) ===\n\n"
        if let body = record.responseBody?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty {
            sb += JsonFormatter.formatJsonString(body)
        } else {
            sb += "(Empty Body)"
        }
        return sb
    }

    public static func buildErrorText(for record: HttpLogRecord) -> String {
        var sb = "=== 异常与失败诊断 (Error / Failure) ===\n\n"
        sb += "• 业务状态: \(record.success ? "成功" : "失败")\n"
        sb += "• 提示信息: \(record.message.isEmpty ? "N/A" : record.message)\n"
        if let err = record.errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines), !err.isEmpty {
            sb += "\n• 异常堆栈:\n\(err)"
        }
        return sb
    }

    /// 根据请求记录自动构建标准可执行的 cURL 命令行（对齐 Android `buildCurlCommand`）。
    public static func buildCurlCommand(_ record: HttpLogRecord) -> String {
        var curl = "curl -X \(record.method)"
        if let headers = record.requestHeaders {
            let lines = headers.components(separatedBy: "\n")
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    let escaped = trimmed.replacingOccurrences(of: "\"", with: "\\\"")
                    curl += " -H \"\(escaped)\""
                }
            }
        }
        if let body = record.requestBody, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let escapedBody = body.replacingOccurrences(of: "'", with: "'\\''")
            curl += " --data-raw '\(escapedBody)'"
        }
        curl += " \"\(record.url)\""
        return curl
    }

    // MARK: - Actions

    @objc private func handleClose() {
        dismiss(animated: true)
    }

    @objc private func handleCopyUrl() {
        guard !throttler.isThrottled() else { return }
        UIPasteboard.general.string = record.url
        ToastView.show("已复制 URL 到剪贴板", in: view)
    }

    @objc private func handleCopyCurl() {
        guard !throttler.isThrottled() else { return }
        UIPasteboard.general.string = Self.buildCurlCommand(record)
        ToastView.show("已复制 cURL 命令到剪贴板", in: view)
    }

    @objc private func handleCopyCurrentTab() {
        guard !throttler.isThrottled() else { return }
        UIPasteboard.general.string = contentTextView.text ?? ""
        ToastView.show("已复制当前页内容到剪贴板", in: view)
    }

    @objc private func handleShareContent(_ sender: UIButton) {
        guard !throttler.isThrottled() else { return }
        let text = contentTextView.text ?? ""
        ShareHelper.shareText(text, from: self, sourceView: sender)
    }
}
#endif

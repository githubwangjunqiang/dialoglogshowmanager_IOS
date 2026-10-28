import Foundation
#if canImport(UIKit)
import UIKit

/// 只读沙盒文件浏览主视图（1:1 对齐 Android `FileBrowserView.java`）。
/// 支持：
/// 1. 顶部「⬅ 返回上一级」与当前路径显示；
/// 2. 目录优先、名称不区分大小写排序；
/// 3. 严格防路径穿越（`PagedTextLoader.isWithinRoot`），严禁通过 `..` 或软链接跳出 `rootPath`；
/// 4. 点击目录进入子目录，点击文件弹出 `FilePreviewViewController`。
@objcMembers
public final class FileBrowserView: UIView, UITableViewDataSource, UITableViewDelegate {

    public weak var hostViewController: UIViewController?

    private struct FileEntry {
        let path: String
        let name: String
        let isDirectory: Bool
        let sizeBytes: Int64
    }

    public let rootPath: String
    private var navigationStack: [String] = []
    private var entries: [FileEntry] = []
    private var loadGeneration: Int = 0
    private var isReleased: Bool = false

    private let ioQueue = DispatchQueue(label: "com.xq.showlog.filebrowser.io", qos: .userInitiated)
    private let throttler = ClickThrottler(intervalMs: ShowLogTheme.throttleMs)

    private let backBtn = UIButton(type: .custom)
    private let pathLabel = UILabel()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let statusLabel = UILabel()
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private weak var activePreviewVC: FilePreviewViewController?

    public init(rootPath: String) {
        self.rootPath = rootPath
        self.navigationStack = [rootPath]
        super.init(frame: .zero)
        setupUI()
        loadCurrentDirectory()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func teardown() {
        isReleased = true
        loadGeneration += 1
        activePreviewVC?.dismiss(animated: false)
        activePreviewVC = nil
        entries.removeAll()
        tableView.reloadData()
    }

    private func setupUI() {
        backgroundColor = .clear

        let headerBar = UIView()
        headerBar.translatesAutoresizingMaskIntoConstraints = false

        backBtn.setTitle("⬅ 返回上一级", for: .normal)
        backBtn.setTitleColor(ShowLogTheme.textPrimary, for: .normal)
        backBtn.titleLabel?.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        backBtn.backgroundColor = ShowLogTheme.bgPill
        backBtn.layer.cornerRadius = 6
        backBtn.contentEdgeInsets = UIEdgeInsets(top: 5, left: 10, bottom: 5, right: 10)
        backBtn.setContentHuggingPriority(.required, for: .horizontal)
        backBtn.translatesAutoresizingMaskIntoConstraints = false
        backBtn.addTarget(self, action: #selector(handleNavigateUp), for: .touchUpInside)

        pathLabel.font = ShowLogTheme.monospacedFont(size: 11.5)
        pathLabel.textColor = ShowLogTheme.textSecondary
        pathLabel.lineBreakMode = .byTruncatingHead
        pathLabel.translatesAutoresizingMaskIntoConstraints = false

        headerBar.addSubview(backBtn)
        headerBar.addSubview(pathLabel)

        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 48
        tableView.register(FileBrowserRowCell.self, forCellReuseIdentifier: FileBrowserRowCell.reuseIdentifier)
        tableView.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        statusLabel.textColor = ShowLogTheme.textSecondary
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.isHidden = true
        statusLabel.isUserInteractionEnabled = true
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        let retryTap = UITapGestureRecognizer(target: self, action: #selector(handleRetryLoad))
        statusLabel.addGestureRecognizer(retryTap)

        loadingIndicator.color = ShowLogTheme.actionBtn
        loadingIndicator.hidesWhenStopped = true
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false

        addSubview(headerBar)
        addSubview(tableView)
        addSubview(statusLabel)
        addSubview(loadingIndicator)

        NSLayoutConstraint.activate([
            headerBar.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            headerBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            headerBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            headerBar.heightAnchor.constraint(equalToConstant: 32),

            backBtn.leadingAnchor.constraint(equalTo: headerBar.leadingAnchor),
            backBtn.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),

            pathLabel.leadingAnchor.constraint(equalTo: backBtn.trailingAnchor, constant: 8),
            pathLabel.trailingAnchor.constraint(equalTo: headerBar.trailingAnchor),
            pathLabel.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),

            tableView.topAnchor.constraint(equalTo: headerBar.bottomAnchor, constant: 6),
            tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: bottomAnchor),

            statusLabel.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: tableView.centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),

            loadingIndicator.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: tableView.centerYAnchor)
        ])
    }

    @objc private func handleNavigateUp() {
        guard !throttler.isThrottled(), !isReleased, navigationStack.count > 1 else { return }
        navigationStack.removeLast()
        loadCurrentDirectory()
    }

    @objc private func handleRetryLoad() {
        guard !throttler.isThrottled(), !isReleased else { return }
        loadCurrentDirectory()
    }

    private func loadCurrentDirectory() {
        guard !isReleased, let currentPath = navigationStack.last else { return }
        pathLabel.text = currentPath
        backBtn.alpha = navigationStack.count > 1 ? 1.0 : 0.45

        loadGeneration += 1
        let expectedGen = loadGeneration

        loadingIndicator.startAnimating()
        statusLabel.isHidden = true
        tableView.isHidden = true

        let root = rootPath
        ioQueue.async { [weak self] in
            var resultEntries: [FileEntry] = []
            var errorMessage: String?

            let fm = FileManager.default
            var isDir: ObjCBool = false

            if !PagedTextLoader.isWithinRoot(rootPath: root, candidatePath: currentPath) {
                errorMessage = "无法访问该目录（超出配置根目录范围）"
            } else if !fm.fileExists(atPath: currentPath, isDirectory: &isDir) {
                errorMessage = "目录不存在"
            } else if !isDir.boolValue {
                errorMessage = "配置的路径不是文件夹"
            } else if !fm.isReadableFile(atPath: currentPath) {
                errorMessage = "无法访问该目录（无读取权限）"
            } else if let children = try? fm.contentsOfDirectory(atPath: currentPath) {
                for name in children {
                    let fullPath = (currentPath as NSString).appendingPathComponent(name)
                    guard PagedTextLoader.isWithinRoot(rootPath: root, candidatePath: fullPath) else {
                        continue
                    }
                    var childIsDir: ObjCBool = false
                    _ = fm.fileExists(atPath: fullPath, isDirectory: &childIsDir)
                    let isFolder = childIsDir.boolValue
                    let size: Int64
                    if isFolder {
                        size = 0
                    } else {
                        let attrs = try? fm.attributesOfItem(atPath: fullPath)
                        size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
                    }
                    resultEntries.append(FileEntry(path: fullPath, name: name, isDirectory: isFolder, sizeBytes: size))
                }
                resultEntries.sort { left, right in
                    if left.isDirectory != right.isDirectory {
                        return left.isDirectory && !right.isDirectory
                    }
                    return left.name.lowercased() < right.name.lowercased()
                }
            } else {
                errorMessage = "无法访问该目录"
            }

            DispatchQueue.main.async {
                guard let self = self, !self.isReleased, expectedGen == self.loadGeneration else { return }
                self.loadingIndicator.stopAnimating()
                self.entries = resultEntries
                self.tableView.reloadData()

                if let err = errorMessage {
                    self.statusLabel.text = err
                    self.statusLabel.isHidden = false
                    self.tableView.isHidden = true
                } else if resultEntries.isEmpty {
                    self.statusLabel.text = "文件夹为空"
                    self.statusLabel.isHidden = false
                    self.tableView.isHidden = true
                } else {
                    self.statusLabel.isHidden = true
                    self.tableView.isHidden = false
                }
            }
        }
    }

    // MARK: - UITableViewDataSource & Delegate

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return entries.count
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: FileBrowserRowCell.reuseIdentifier, for: indexPath) as? FileBrowserRowCell else {
            return UITableViewCell()
        }
        let entry = entries[indexPath.row]
        cell.configure(name: entry.name, isDirectory: entry.isDirectory, sizeBytes: entry.sizeBytes)
        return cell
    }

    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard !throttler.isThrottled() else { return }
        let entry = entries[indexPath.row]

        guard PagedTextLoader.isWithinRoot(rootPath: rootPath, candidatePath: entry.path) else {
            ToastView.show("无法访问该路径（超出配置根目录范围）", in: self)
            return
        }

        if entry.isDirectory {
            navigationStack.append(entry.path)
            loadCurrentDirectory()
        } else {
            guard let hostVC = hostViewController ?? findResponderViewController() else { return }
            activePreviewVC?.dismiss(animated: false)
            let previewVC = FilePreviewViewController(rootPath: rootPath, filePath: entry.path)
            activePreviewVC = previewVC
            hostVC.present(previewVC, animated: true)
        }
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

private final class FileBrowserRowCell: UITableViewCell {
    static let reuseIdentifier = "ShowLog.FileBrowserRowCell"

    private let cardView = UIView()
    private let nameLabel = UILabel()
    private let sizeLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        cardView.backgroundColor = ShowLogTheme.bgCard
        cardView.layer.cornerRadius = 7
        cardView.layer.borderWidth = 1
        cardView.layer.borderColor = ShowLogTheme.bgCardStroke.cgColor
        cardView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(cardView)

        nameLabel.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        nameLabel.textColor = ShowLogTheme.textPrimary
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        sizeLabel.font = ShowLogTheme.monospacedFont(size: 11.5)
        sizeLabel.textColor = ShowLogTheme.textSecondary
        sizeLabel.textAlignment = .right
        sizeLabel.setContentHuggingPriority(.required, for: .horizontal)
        sizeLabel.translatesAutoresizingMaskIntoConstraints = false

        cardView.addSubview(nameLabel)
        cardView.addSubview(sizeLabel)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 3),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -3),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),

            nameLabel.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            nameLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 12),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: sizeLabel.leadingAnchor, constant: -8),

            sizeLabel.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            sizeLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -12)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(name: String, isDirectory: Bool, sizeBytes: Int64) {
        nameLabel.text = isDirectory ? "📁 \(name)" : "📄 \(name)"
        sizeLabel.text = isDirectory ? "目录 ❯" : AppDeviceInfoCollector.formatBytes(sizeBytes)
    }
}
#endif

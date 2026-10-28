import Foundation

/// 全局 SDK 运行配置。
/// 为什么这样做：
/// 采用参数化不可变配置与安全范围保护（区间钳制），既让开发者能自由调整数据库容量上限（默认 10000 条）和脱敏规则，
/// 又能防止极端参数引发 OOM 或磁盘耗尽。
@objcMembers
public final class ShowLogConfig: NSObject {

    public static let DEFAULT_MAX_DATABASE_LIMIT: Int = 10000
    public static let MIN_DATABASE_LIMIT: Int = 100
    public static let MAX_DATABASE_LIMIT: Int = 50000
    public static let DEFAULT_MAX_BODY_BYTES: Int = 256 * 1024 // 256KB 截断保护
    public static let MIN_BODY_BYTES: Int = 1024

    /// SQLite 数据库保留网络日志的最大条数，默认 10000 条（区间钳制 100 ~ 50000）。
    public let maxDatabaseLogLimit: Int

    /// 单个请求体/响应体允许读取和缓存的最大字节数，超出部分安全截断（最低 1024 字节）。
    public let maxBodyBytes: Int

    /// 敏感请求头集合，拦截器会自动对其打码脱敏（忽略大小写匹配）。
    public let redactHeaders: Set<String>

    /// 是否启用网络日志监控与调试功能。
    /// 生产包可配置为 false（如 `#if DEBUG` 传入 true，Release 传入 false），
    /// 此时 SDK 内部拦截器 100% 直通放行，零内存分配、零后台写库，悬浮球与控制台完全静默。
    public let enabled: Bool

    /// 是否在 App 界面上显示免权限吸边悬浮球入口。
    public let showFloatingView: Bool

    /// 文件浏览功能的根目录路径；为空或空白字符串时归一化为 nil，主中枢不展示文件浏览 Tab。
    public let fileBrowserRootPath: String?

    /// 文件浏览 Tab 的自定义标题；为空或空白字符串时归一化为 nil，UI 回退展示“文件浏览”。
    public let fileBrowserTabTitle: String?

    /// 是否自动将 ShowLogURLProtocol 注入到 URLSessionConfiguration.default / .ephemeral（默认 true）。
    public let enableURLSessionSwizzling: Bool

    private init(builder: Builder) {
        self.maxDatabaseLogLimit = max(
            Self.MIN_DATABASE_LIMIT,
            min(builder.maxDatabaseLogLimitValue, Self.MAX_DATABASE_LIMIT)
        )
        self.maxBodyBytes = max(Self.MIN_BODY_BYTES, builder.maxBodyBytesValue)
        self.redactHeaders = builder.redactHeadersValue
        self.enabled = builder.enabledValue
        self.showFloatingView = builder.showFloatingViewValue
        self.fileBrowserRootPath = Self.normalizePath(builder.fileBrowserRootPathValue)
        self.fileBrowserTabTitle = Self.normalizeTitle(builder.fileBrowserTabTitleValue)
        self.enableURLSessionSwizzling = builder.enableURLSessionSwizzlingValue
        super.init()
    }

    /// 路径首尾空格可能是合法文件名的一部分，仅使用 trim 判断是否为空白字符串，非空时保留原始路径。
    private static func normalizePath(_ value: String?) -> String? {
        guard let value = value else { return nil }
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
    }

    private static func normalizeTitle(_ value: String?) -> String? {
        guard let value = value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// 判断指定 Header 名称是否属于需脱敏的敏感头（忽略大小写）。
    public func shouldRedactHeader(_ headerName: String) -> Bool {
        let lower = headerName.lowercased()
        return redactHeaders.contains { $0.lowercased() == lower }
    }

    /// 获取默认配置实例。
    public static func defaultConfig() -> ShowLogConfig {
        return Builder().build()
    }

    /// 链式配置构建器（支持 Swift 与 Objective-C 调用）。
    @objc(ShowLogConfigBuilder)
    @objcMembers
    public final class Builder: NSObject {
        fileprivate var maxDatabaseLogLimitValue: Int = ShowLogConfig.DEFAULT_MAX_DATABASE_LIMIT
        fileprivate var maxBodyBytesValue: Int = ShowLogConfig.DEFAULT_MAX_BODY_BYTES
        fileprivate var redactHeadersValue: Set<String> = [
            "Authorization",
            "Cookie",
            "Set-Cookie",
            "token",
            "access_token"
        ]
        fileprivate var enabledValue: Bool = true
        fileprivate var showFloatingViewValue: Bool = true
        fileprivate var fileBrowserRootPathValue: String?
        fileprivate var fileBrowserTabTitleValue: String?
        fileprivate var enableURLSessionSwizzlingValue: Bool = true

        public override init() {
            super.init()
        }

        /// 设置数据库最多保留的历史网络日志条数（默认 10000 条，允许范围 100 ~ 50000）。
        @discardableResult
        public func maxDatabaseLogLimit(_ limit: Int) -> Builder {
            self.maxDatabaseLogLimitValue = limit
            return self
        }

        /// 设置报文读取最大截断字节数（默认 256KB，最低钳制 1024 字节）。
        @discardableResult
        public func maxBodyBytes(_ bytes: Int) -> Builder {
            self.maxBodyBytesValue = bytes
            return self
        }

        /// 添加需要脱敏的敏感 Header 键名。
        @discardableResult
        public func addRedactHeader(_ headerName: String) -> Builder {
            let trimmed = headerName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                self.redactHeadersValue.insert(trimmed)
            }
            return self
        }

        /// 设置是否启用 SDK（默认 true）。生产包建议设为 false。
        @discardableResult
        public func enabled(_ enabled: Bool) -> Builder {
            self.enabledValue = enabled
            return self
        }

        /// 是否自动在页面上显示调试悬浮球入口（默认 true）。
        @discardableResult
        public func showFloatingView(_ show: Bool) -> Builder {
            self.showFloatingViewValue = show
            return self
        }

        /// 设置文件浏览主 Tab 的根目录；为空或空白字符串时不显示文件浏览 Tab。
        @discardableResult
        public func fileBrowserRootPath(_ path: String?) -> Builder {
            self.fileBrowserRootPathValue = path
            return self
        }

        /// 设置文件浏览主 Tab 标题；为空时显示默认标题“文件浏览”。
        @discardableResult
        public func fileBrowserTabTitle(_ title: String?) -> Builder {
            self.fileBrowserTabTitleValue = title
            return self
        }

        /// 设置是否自动注入 URLSessionConfiguration.default / .ephemeral（默认 true）。
        @discardableResult
        public func enableURLSessionSwizzling(_ enable: Bool) -> Builder {
            self.enableURLSessionSwizzlingValue = enable
            return self
        }

        public func build() -> ShowLogConfig {
            return ShowLogConfig(builder: self)
        }
    }
}

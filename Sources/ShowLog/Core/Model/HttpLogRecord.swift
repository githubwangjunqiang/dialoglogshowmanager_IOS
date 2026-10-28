import Foundation

/// HTTP/HTTPS 网络日志不可变实体（对齐 Android `HttpLogRecord.java` 全部 21 个核心属性）。
/// 为什么这样做：
/// 1. 采用不可变数据模型（所有属性为 `let`），确保高并发网络请求、后台异步写库与 UI 渲染之间绝对线程安全；
/// 2. 覆盖接口诊断所需的全维度数据（URL、Host、Path、Method、状态码、Headers、Body、耗时、时间戳、异常信息及尺寸）；
/// 3. 引入业务 `success` 与 `message` 字段，将业务成功与否同 HTTP 传输状态码解耦。
@objcMembers
public final class HttpLogRecord: NSObject {

    /// 数据库自增主键 ID；在尚未落盘的内存缓冲队列中为唯一的负数临时 ID（-1, -2, ...）。
    public let id: Int64

    /// 唯一跟踪 ID，用于内存缓冲与数据库去重合并。
    public let traceId: String

    /// 完整请求 URL。
    public let url: String

    /// 主机域名，如 api.example.com，用于建立索引和快速检索。
    public let host: String

    /// 路径部分，如 /api/v1/user/login，用于接口名折叠分组。
    public let path: String

    /// 请求方式，如 GET, POST, PUT, DELETE。
    public let method: String

    /// HTTP 响应状态码，如 200, 404, 500；若请求在网络传输层发生异常未完成，则固定为 -1。
    public let statusCode: Int

    /// HTTP 传输层状态码别名（与 statusCode 对等）。
    public let httpCode: Int

    /// 本次接口调用在业务上是否算作成功（控制台以此字段为准决定红绿着色与筛选）。
    public let success: Bool

    /// 接口返回的业务提示信息、错误说明或状态描述。
    public let message: String

    /// 请求头格式化文本。
    public let requestHeaders: String?

    /// 请求体（已经过安全截断、脱敏与 JSON 美化）。
    public let requestBody: String?

    /// 响应头格式化文本。
    public let responseHeaders: String?

    /// 响应体（已经过自动解压、安全截断与 JSON 美化）。
    public let responseBody: String?

    /// 报文 MIME 类型，如 application/json, text/plain。
    public let contentType: String?

    /// 请求体字节数。
    public let requestSize: Int64

    /// 响应体字节数。
    public let responseSize: Int64

    /// 完整耗时（毫秒）。
    public let durationMs: Int64

    /// 请求发起时间戳（毫秒），用于默认当天筛选及时间排序。
    public let timestamp: Int64

    /// 异常错误信息与堆栈摘要；成功请求为 nil。
    public let errorMessage: String?

    /// 是否失败（恒等于 `!success`）。
    public let isFailed: Bool

    private init(builder: Builder) {
        self.id = builder.idValue
        if let tid = builder.traceIdValue, !tid.isEmpty {
            self.traceId = tid
        } else {
            self.traceId = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }
        self.url = builder.urlValue
        self.host = builder.hostValue
        self.path = builder.pathValue
        let upperMethod = builder.methodValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.method = upperMethod.isEmpty ? "GET" : upperMethod
        self.statusCode = builder.statusCodeValue
        self.httpCode = builder.httpCodeValue != 0 ? builder.httpCodeValue : builder.statusCodeValue
        self.success = builder.successValue
        if let msg = builder.messageValue, !msg.isEmpty {
            self.message = msg
        } else {
            self.message = builder.successValue ? "OK" : "FAILED"
        }
        self.requestHeaders = builder.requestHeadersValue
        self.requestBody = builder.requestBodyValue
        self.responseHeaders = builder.responseHeadersValue
        self.responseBody = builder.responseBodyValue
        self.contentType = builder.contentTypeValue
        self.requestSize = builder.requestSizeValue
        self.responseSize = builder.responseSizeValue
        self.durationMs = builder.durationMsValue
        self.timestamp = builder.timestampValue > 0 ? builder.timestampValue : Self.currentTimeMillis()
        self.errorMessage = builder.errorMessageValue
        self.isFailed = !builder.successValue
        super.init()
    }

    public static func currentTimeMillis() -> Int64 {
        return Int64(Date().timeIntervalSince1970 * 1000.0)
    }

    /// 根据当前记录创建带新数据库自增 ID（或临时负数 ID）的副本。
    public func withId(_ newId: Int64) -> HttpLogRecord {
        return Builder(copy: self).id(newId).build()
    }

    /// 从强制纯抽象契约 `HttpLogPayload` 转换为不可变实体 `HttpLogRecord`。
    public static func fromPayload(_ payload: HttpLogPayload) -> HttpLogRecord {
        let rawUrl = payload.getUrl()
        let (host, path) = extractHostAndPath(from: rawUrl)

        let requestBodyStr = JsonFormatter.formatAny(payload.getRequestBody())
        let responseBodyStr = JsonFormatter.formatAny(payload.getResponseBody())

        let config = ShowLog.getConfig()
        let reqHeadersStr = formatHeaders(payload.getRequestHeaders(), config: config)
        let resHeadersStr = formatHeaders(payload.getResponseHeaders(), config: config)

        let isSuccess = payload.isSuccess()
        let msg = payload.getMessage()

        var errorMsg: String?
        if let err = payload.getError() {
            let nsErr = err as NSError
            errorMsg = "\(nsErr.domain) (code: \(nsErr.code)): \(nsErr.localizedDescription)\n\(String(describing: err))"
        } else if !isSuccess {
            errorMsg = msg
        }

        let reqSize = Int64(requestBodyStr?.utf8.count ?? 0)
        let resSize = Int64(responseBodyStr?.utf8.count ?? 0)
        let contentType = extractContentType(from: payload.getResponseHeaders()) ?? extractContentType(from: payload.getRequestHeaders())

        return Builder()
            .url(rawUrl)
            .host(host)
            .path(path)
            .method(payload.getMethod())
            .statusCode(payload.getHttpCode())
            .httpCode(payload.getHttpCode())
            .success(isSuccess)
            .message(msg)
            .requestHeaders(reqHeadersStr)
            .requestBody(requestBodyStr)
            .responseHeaders(resHeadersStr)
            .responseBody(responseBodyStr)
            .contentType(contentType)
            .durationMs(payload.getDurationMs())
            .timestamp(currentTimeMillis())
            .requestSize(reqSize)
            .responseSize(resSize)
            .errorMessage(errorMsg)
            .isFailed(!isSuccess)
            .build()
    }

    /// 安全解析 URL 的 host 与 path；解析失败时兜底 host = "unknown", path = url。
    public static func extractHostAndPath(from urlString: String) -> (host: String, path: String) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ("unknown", "")
        }
        if let components = URLComponents(string: trimmed),
           let scheme = components.scheme, !scheme.isEmpty,
           let host = components.host, !host.isEmpty {
            let path = components.path.isEmpty ? "/" : components.path
            return (host, path)
        }
        if let url = URL(string: trimmed),
           let scheme = url.scheme, !scheme.isEmpty,
           let host = url.host, !host.isEmpty {
            let path = url.path.isEmpty ? "/" : url.path
            return (host, path)
        }
        return ("unknown", urlString)
    }

    public static func formatHeaders(_ headers: [String: String]?, config: ShowLogConfig? = nil) -> String? {
        guard let headers = headers, !headers.isEmpty else { return nil }
        let sortedKeys = headers.keys.sorted()
        var lines: [String] = []
        for key in sortedKeys {
            let rawValue = headers[key] ?? ""
            if let cfg = config, cfg.shouldRedactHeader(key) {
                lines.append("\(key): ****** [REDACTED]")
            } else {
                lines.append("\(key): \(rawValue)")
            }
        }
        return lines.joined(separator: "\n")
    }

    public static func extractContentType(from headers: [String: String]?) -> String? {
        guard let headers = headers else { return nil }
        for (key, value) in headers where key.caseInsensitiveCompare("Content-Type") == .orderedSame {
            return value
        }
        return nil
    }

    /// 构造器类，支持链式构建和字段安全校验。
    @objc(HttpLogRecordBuilder)
    @objcMembers
    public final class Builder: NSObject {
        fileprivate var idValue: Int64 = 0
        fileprivate var traceIdValue: String?
        fileprivate var urlValue: String = ""
        fileprivate var hostValue: String = ""
        fileprivate var pathValue: String = ""
        fileprivate var methodValue: String = "GET"
        fileprivate var statusCodeValue: Int = 200
        fileprivate var httpCodeValue: Int = 200
        fileprivate var successValue: Bool = true
        fileprivate var messageValue: String? = "OK"
        fileprivate var requestHeadersValue: String?
        fileprivate var requestBodyValue: String?
        fileprivate var responseHeadersValue: String?
        fileprivate var responseBodyValue: String?
        fileprivate var contentTypeValue: String?
        fileprivate var requestSizeValue: Int64 = 0
        fileprivate var responseSizeValue: Int64 = 0
        fileprivate var durationMsValue: Int64 = 0
        fileprivate var timestampValue: Int64 = 0
        fileprivate var errorMessageValue: String?
        fileprivate var isFailedValue: Bool = false

        public override init() {
            super.init()
        }

        public init(copy: HttpLogRecord) {
            self.idValue = copy.id
            self.traceIdValue = copy.traceId
            self.urlValue = copy.url
            self.hostValue = copy.host
            self.pathValue = copy.path
            self.methodValue = copy.method
            self.statusCodeValue = copy.statusCode
            self.httpCodeValue = copy.httpCode
            self.successValue = copy.success
            self.messageValue = copy.message
            self.requestHeadersValue = copy.requestHeaders
            self.requestBodyValue = copy.requestBody
            self.responseHeadersValue = copy.responseHeaders
            self.responseBodyValue = copy.responseBody
            self.contentTypeValue = copy.contentType
            self.requestSizeValue = copy.requestSize
            self.responseSizeValue = copy.responseSize
            self.durationMsValue = copy.durationMs
            self.timestampValue = copy.timestamp
            self.errorMessageValue = copy.errorMessage
            self.isFailedValue = copy.isFailed
            super.init()
        }

        @discardableResult
        public func id(_ id: Int64) -> Builder {
            self.idValue = id
            return self
        }

        @discardableResult
        public func traceId(_ traceId: String?) -> Builder {
            self.traceIdValue = traceId
            return self
        }

        @discardableResult
        public func url(_ url: String?) -> Builder {
            self.urlValue = url ?? ""
            return self
        }

        @discardableResult
        public func host(_ host: String?) -> Builder {
            self.hostValue = host ?? ""
            return self
        }

        @discardableResult
        public func path(_ path: String?) -> Builder {
            self.pathValue = path ?? ""
            return self
        }

        @discardableResult
        public func method(_ method: String?) -> Builder {
            self.methodValue = method ?? "GET"
            return self
        }

        @discardableResult
        public func statusCode(_ statusCode: Int) -> Builder {
            self.statusCodeValue = statusCode
            self.httpCodeValue = statusCode
            return self
        }

        @discardableResult
        public func httpCode(_ httpCode: Int) -> Builder {
            self.httpCodeValue = httpCode
            self.statusCodeValue = httpCode
            return self
        }

        @discardableResult
        public func success(_ success: Bool) -> Builder {
            self.successValue = success
            self.isFailedValue = !success
            return self
        }

        @discardableResult
        public func message(_ message: String?) -> Builder {
            self.messageValue = message
            return self
        }

        @discardableResult
        public func requestHeaders(_ requestHeaders: String?) -> Builder {
            self.requestHeadersValue = requestHeaders
            return self
        }

        @discardableResult
        public func requestBody(_ requestBody: String?) -> Builder {
            self.requestBodyValue = requestBody
            return self
        }

        @discardableResult
        public func responseHeaders(_ responseHeaders: String?) -> Builder {
            self.responseHeadersValue = responseHeaders
            return self
        }

        @discardableResult
        public func responseBody(_ responseBody: String?) -> Builder {
            self.responseBodyValue = responseBody
            return self
        }

        @discardableResult
        public func contentType(_ contentType: String?) -> Builder {
            self.contentTypeValue = contentType
            return self
        }

        @discardableResult
        public func requestSize(_ requestSize: Int64) -> Builder {
            self.requestSizeValue = requestSize
            return self
        }

        @discardableResult
        public func responseSize(_ responseSize: Int64) -> Builder {
            self.responseSizeValue = responseSize
            return self
        }

        @discardableResult
        public func durationMs(_ durationMs: Int64) -> Builder {
            self.durationMsValue = durationMs
            return self
        }

        @discardableResult
        public func timestamp(_ timestamp: Int64) -> Builder {
            self.timestampValue = timestamp
            return self
        }

        @discardableResult
        public func errorMessage(_ errorMessage: String?) -> Builder {
            self.errorMessageValue = errorMessage
            return self
        }

        @discardableResult
        public func isFailed(_ isFailed: Bool) -> Builder {
            self.isFailedValue = isFailed
            self.successValue = !isFailed
            return self
        }

        public func build() -> HttpLogRecord {
            return HttpLogRecord(builder: self)
        }
    }
}

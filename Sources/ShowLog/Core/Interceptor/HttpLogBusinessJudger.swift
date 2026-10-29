import Foundation

/// 接口上下文只读数据快照（对齐 Android `HttpLogBusinessJudger.RequestContext`）。
@objcMembers
public final class HttpLogRequestContext: NSObject {
    public let url: String
    public let host: String
    public let path: String
    public let method: String
    public let httpCode: Int
    public let durationMs: Int64
    public let requestHeaders: [String: String]?
    public let responseHeaders: [String: String]?
    public let requestBody: String?
    public let responseBody: String?
    public let error: Error?

    public init(
        url: String,
        host: String? = nil,
        path: String? = nil,
        method: String,
        httpCode: Int,
        durationMs: Int64,
        requestHeaders: [String: String]? = nil,
        responseHeaders: [String: String]? = nil,
        requestBody: String? = nil,
        responseBody: String? = nil,
        error: Error? = nil
    ) {
        self.url = url
        let parsed = HttpLogRecord.extractHostAndPath(from: url)
        self.host = host ?? parsed.host
        self.path = path ?? parsed.path
        self.method = method.isEmpty ? "GET" : method.uppercased()
        self.httpCode = httpCode
        self.durationMs = durationMs
        self.requestHeaders = requestHeaders
        self.responseHeaders = responseHeaders
        self.requestBody = requestBody
        self.responseBody = responseBody
        self.error = error
        super.init()
    }

    public func getUrl() -> String { url }
    public func getHost() -> String { host }
    public func getPath() -> String { path }
    public func getMethod() -> String { method }
    public func getHttpCode() -> Int { httpCode }
    public var statusCode: Int { httpCode }
    public func getDurationMs() -> Int64 { durationMs }
    public func getRequestHeaders() -> [String: String]? { requestHeaders }
    public func getResponseHeaders() -> [String: String]? { responseHeaders }
    public func getRequestBody() -> String? { requestBody }
    public func getResponseBody() -> String? { responseBody }
    public func getError() -> Error? { error }

    /// 便捷辅助方法：尝试将响应体解析为 JSON 字典（解析失败或为空时返回 nil）。
    public func optResponseBodyAsJson() -> [String: Any]? {
        guard let body = responseBody?.trimmingCharacters(in: .whitespacesAndNewlines),
              !body.isEmpty,
              let data = body.data(using: .utf8) else {
            return nil
        }
        return (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any]
    }
}

/// 业务裁决结果（对齐 Android `HttpLogBusinessJudger.JudgementResult`）。
@objcMembers
public final class HttpLogJudgementResult: NSObject {
    public let success: Bool
    public let message: String

    public init(success: Bool, message: String?) {
        self.success = success
        if let msg = message, !msg.isEmpty {
            self.message = msg
        } else {
            self.message = success ? "业务请求成功" : "业务请求失败"
        }
        super.init()
    }

    public func isSuccess() -> Bool { success }
    public func getMessage() -> String { message }

    public static func successResult() -> HttpLogJudgementResult {
        return HttpLogJudgementResult(success: true, message: "OK")
    }

    public static func success(_ message: String?) -> HttpLogJudgementResult {
        return HttpLogJudgementResult(success: true, message: message ?? "OK")
    }

    public static func failure(_ message: String?) -> HttpLogJudgementResult {
        return HttpLogJudgementResult(success: false, message: message ?? "业务请求失败")
    }

    /// 便捷业务成功裁决工厂（对齐文档推荐语法）。
    public static func businessSuccess(businessCode: String = "200") -> HttpLogJudgementResult {
        return HttpLogJudgementResult(success: true, message: "业务成功(code=\(businessCode))")
    }

    /// 便捷业务失败裁决工厂（对齐文档推荐语法）。
    public static func businessFailure(businessCode: String, errorMessage: String) -> HttpLogJudgementResult {
        return HttpLogJudgementResult(success: false, message: "\(errorMessage)(code=\(businessCode))")
    }

    /// 便捷系统/传输异常裁决工厂（对齐文档推荐语法）。
    public static func systemError(errorCode: String, message: String) -> HttpLogJudgementResult {
        return HttpLogJudgementResult(success: false, message: "\(message)(error=\(errorCode))")
    }
}

/// 业务结果与成功判定拦截器协议（对齐 Android `HttpLogBusinessJudger`）。
/// 为什么这样做：
/// 在自动拦截场景下，默认只根据 HTTP 2xx 判定成功与否。
/// 业务通过配置此拦截器，可根据自定义报文格式（如业务 code == 0）动态裁决最终的成功/失败状态与展示文本。
@objc
public protocol HttpLogBusinessJudger: NSObjectProtocol {
    func judge(_ context: HttpLogRequestContext) -> HttpLogJudgementResult
}

/// 支持闭包形式的业务裁决适配器。
@objcMembers
internal final class ClosureBusinessJudger: NSObject, HttpLogBusinessJudger {
    private let block: (HttpLogRequestContext) -> HttpLogJudgementResult

    init(block: @escaping (HttpLogRequestContext) -> HttpLogJudgementResult) {
        self.block = block
        super.init()
    }

    func judge(_ context: HttpLogRequestContext) -> HttpLogJudgementResult {
        return block(context)
    }
}

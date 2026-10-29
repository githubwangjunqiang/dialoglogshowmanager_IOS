import Foundation

/// 非 URLSession 或自定义网络库统一上报强契约协议。
/// 为什么全部采用纯抽象协议方法（无 extension 默认实现）：
/// 确保开发者在 Xcode 中实现该协议时，编译器强制要求显式实现全部 11 个方法，
/// 支持 IDE 一键 Fix-it 自动补全全部方法骨架，有值返回值，无值明确返回 nil，彻底告别翻查文档。
@objc
public protocol HttpLogPayload: NSObjectProtocol {

    /// 1. 请求完整 URL（必填，不可为空）。
    /// 例如："https://api.example.com/v1/user/login"
    func getUrl() -> String

    /// 2. 请求方式（必填，不可为空）。
    /// 例如："GET", "POST", "PUT", "DELETE"
    func getMethod() -> String

    /// 3. HTTP 传输层响应状态码。
    /// 例如：200, 404, 500；若网络断开或握手失败未收到响应则传 -1。
    func getHttpCode() -> Int

    /// 4. 接口返回的业务提示信息、错误说明或状态描述（必填）。
    /// 例如："OK", "登录成功", "token已过期", "无法连接到服务器"
    func getMessage() -> String

    /// 5. 接口本次调用业务上是否算作成功。
    /// 注意：控制台的状态指示、红绿染色以及“成功/失败”筛选分类严格以此字段为金标准！
    func isSuccess() -> Bool

    /// 6. 本次请求完整耗时（毫秒）。
    func getDurationMs() -> Int64

    /// 7. 请求 Header 字典（若无自定义请求头，明确 return nil 即可）。
    func getRequestHeaders() -> [String: String]?

    /// 8. 响应 Header 字典（若无响应头，明确 return nil 即可）。
    func getResponseHeaders() -> [String: String]?

    /// 9. 请求报文体（支持传入 `[String: Any]`、`[Any]`、`Data` 或 JSON `String`；无请求体明确 return nil 即可）。
    /// 内部会自动将其转换为 2 空格美化缩进的 JSON 字符串持久化。
    func getRequestBody() -> Any?

    /// 10. 响应报文体（支持传入 `[String: Any]`、`[Any]`、`Data` 或 JSON `String`；无响应体明确 return nil 即可）。
    /// 内部会自动将其转换为 2 空格美化缩进的 JSON 字符串持久化。
    func getResponseBody() -> Any?

    /// 11. 异常错误对象（若发生 Error / NSError 传入此对象；成功请求明确 return nil 即可）。
    func getError() -> Error?
}

/// 开箱即用的强契约上报事件模型，免去手动实现全部协议方法的繁琐步骤。
@objcMembers
public class CustomHttpLogPayload: NSObject, HttpLogPayload {
    public var url: String
    public var method: String
    public var httpCode: Int
    public var message: String
    public var success: Bool
    public var durationMs: Int64
    public var requestHeaders: [String: String]?
    public var responseHeaders: [String: String]?
    public var requestBody: Any?
    public var responseBody: Any?
    public var error: Error?

    public init(
        url: String,
        method: String = "POST",
        httpCode: Int = 200,
        message: String = "OK",
        success: Bool = true,
        durationMs: Int64 = 0,
        requestHeaders: [String: String]? = nil,
        responseHeaders: [String: String]? = nil,
        requestBody: Any? = nil,
        responseBody: Any? = nil,
        error: Error? = nil
    ) {
        self.url = url
        self.method = method
        self.httpCode = httpCode
        self.message = message
        self.success = success
        self.durationMs = durationMs
        self.requestHeaders = requestHeaders
        self.responseHeaders = responseHeaders
        self.requestBody = requestBody
        self.responseBody = responseBody
        self.error = error
        super.init()
    }

    public func getUrl() -> String { url }
    public func getMethod() -> String { method }
    public func getHttpCode() -> Int { httpCode }
    public func getMessage() -> String { message }
    public func isSuccess() -> Bool { success }
    public func getDurationMs() -> Int64 { durationMs }
    public func getRequestHeaders() -> [String: String]? { requestHeaders }
    public func getResponseHeaders() -> [String: String]? { responseHeaders }
    public func getRequestBody() -> Any? { requestBody }
    public func getResponseBody() -> Any? { responseBody }
    public func getError() -> Error? { error }
}

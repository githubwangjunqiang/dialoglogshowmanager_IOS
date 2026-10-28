import Foundation

/// 接口名（Path）聚合折叠展示模型（对齐 Android `HttpLogGroupItem.java`）。
/// 为什么这样做：
/// 当用户开启“分组”模式时，同类接口聚合为一个父级卡片展示，清晰呈现总调用次数、失败次数、最新耗时与业务状态，避免高频接口刷屏。
@objcMembers
public final class HttpLogGroupItem: NSObject {

    /// 接口路径，如 `/api/v1/user/login`。
    public let path: String

    /// 请求方法，如 `POST`。
    public let method: String

    /// 所属域名 Host。
    public let host: String

    /// 该分组下包含的全部实际请求记录列表。
    public private(set) var records: [HttpLogRecord] = []

    /// 该接口调用的总次数。
    public private(set) var totalCount: Int = 0

    /// 该接口失败的次数。
    public private(set) var failureCount: Int = 0

    /// 最新一次调用的发起时间戳（毫秒）。
    public private(set) var latestTimestamp: Int64 = 0

    /// 最新一次调用的耗时（毫秒）。
    public private(set) var latestDurationMs: Int64 = 0

    /// 最新一次调用的状态码。
    public private(set) var latestStatusCode: Int = 0

    /// 最新一次调用是否业务成功。
    public private(set) var latestSuccess: Bool = true

    /// 在 UI 列表中是否处于展开状态。
    public var isExpanded: Bool = false

    public init(path: String, method: String, host: String) {
        self.path = path
        self.method = method
        self.host = host
        super.init()
    }

    /// 向分组中追加一条请求记录并更新最新摘要统计。
    public func addRecord(_ record: HttpLogRecord) {
        records.append(record)
        totalCount += 1
        if record.isFailed {
            failureCount += 1
        }
        if record.timestamp >= latestTimestamp {
            latestTimestamp = record.timestamp
            latestDurationMs = record.durationMs
            latestStatusCode = record.statusCode
            latestSuccess = record.success
        }
    }
}

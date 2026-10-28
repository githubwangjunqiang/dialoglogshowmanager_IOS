import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// 新网络日志实时监听协议（主线程回调）。
@objc
public protocol OnNewLogListener: AnyObject {
    func onNewLog(_ record: HttpLogRecord)
}

/// 全局网络日志高性能双层仓储（内存缓冲队列 + 500ms 批量单事务 SQLite 持久化 + 双层 Hybrid-Read）。
/// 对齐 Android `HttpLogRepository.java`。
@objcMembers
public final class HttpLogRepository: NSObject {

    public static let shared = HttpLogRepository()

    private var dbHelper: HttpLogSqliteHelper
    private var config: ShowLogConfig = ShowLogConfig.defaultConfig()
    private let queueLock = NSLock()
    private var pendingQueue: [HttpLogRecord] = []
    private var nextTempId: Int64 = -1
    private let ioQueue = DispatchQueue(label: "com.xq.showlog.repository.io", qos: .utility)
    private var flushTimer: DispatchSourceTimer?

    private final class WeakListenerBox {
        weak var listener: OnNewLogListener?
        init(_ listener: OnNewLogListener) {
            self.listener = listener
        }
    }

    private let listenerLock = NSLock()
    private var listeners: [WeakListenerBox] = []

    public override init() {
        self.dbHelper = HttpLogSqliteHelper()
        super.init()
        startPeriodicFlushTimer()
        registerAppLifecycleObservers()
    }

    /// 供单元测试或自定义初始化使用的构造器。
    public init(dbHelper: HttpLogSqliteHelper, config: ShowLogConfig) {
        self.dbHelper = dbHelper
        self.config = config
        super.init()
        startPeriodicFlushTimer()
    }

    deinit {
        flushTimer?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    public func configure(with config: ShowLogConfig, customDbHelper: HttpLogSqliteHelper? = nil) {
        queueLock.lock()
        self.config = config
        if let helper = customDbHelper {
            self.dbHelper = helper
        }
        queueLock.unlock()
    }

    private func startPeriodicFlushTimer() {
        let timer = DispatchSource.makeTimerSource(queue: ioQueue)
        timer.schedule(deadline: .now() + .milliseconds(500), repeating: .milliseconds(500))
        timer.setEventHandler { [weak self] in
            self?.flushPendingToDisk()
        }
        timer.resume()
        self.flushTimer = timer
    }

    private func registerAppLifecycleObservers() {
        #if canImport(UIKit)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onAppWillResignOrTerminate),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onAppWillResignOrTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
        #endif
    }

    @objc private func onAppWillResignOrTerminate() {
        ioQueue.async { [weak self] in
            self?.flushPendingToDisk()
        }
    }

    /// 生产者入口：极速将一条网络日志推入内存缓冲队列，并主线程实时通知已打开的控制台。
    public func enqueueLog(_ record: HttpLogRecord) {
        guard ShowLog.isEnabled() else {
            return
        }

        queueLock.lock()
        let queuedRecord: HttpLogRecord
        if record.id == 0 {
            let tempId = nextTempId
            nextTempId -= 1
            queuedRecord = record.withId(tempId)
        } else {
            queuedRecord = record
        }
        pendingQueue.append(queuedRecord)
        queueLock.unlock()

        notifyLiveListeners(queuedRecord)
    }

    /// 注册控制台实时刷新监听器（弱引用持有）。
    public func registerNewLogListener(_ listener: OnNewLogListener) {
        listenerLock.lock()
        defer { listenerLock.unlock() }
        listeners.removeAll { $0.listener == nil || $0.listener === listener }
        listeners.append(WeakListenerBox(listener))
    }

    /// 注销实时监听器。
    public func unregisterNewLogListener(_ listener: OnNewLogListener) {
        listenerLock.lock()
        defer { listenerLock.unlock() }
        listeners.removeAll { $0.listener == nil || $0.listener === listener }
    }

    private func notifyLiveListeners(_ record: HttpLogRecord) {
        listenerLock.lock()
        listeners.removeAll { $0.listener == nil }
        let activeListeners = listeners.compactMap { $0.listener }
        listenerLock.unlock()

        guard !activeListeners.isEmpty else { return }
        DispatchQueue.main.async {
            for listener in activeListeners {
                listener.onNewLog(record)
            }
        }
    }

    /// 将内存待写队列中的所有日志批量单事务写入 SQLite 并执行 LRU 修剪。
    public func flushPendingToDisk() {
        queueLock.lock()
        guard !pendingQueue.isEmpty else {
            queueLock.unlock()
            return
        }
        let batch = pendingQueue
        pendingQueue.removeAll()
        let helper = dbHelper
        let maxLimit = config.maxDatabaseLogLimit
        queueLock.unlock()

        helper.insertBatch(batch)
        helper.trimToLimit(maxLimit)
    }

    /// 双层协同读取（Hybrid-Read）：查询指定时间范围内的全部日志（合并数据库已落盘数据 + 内存未刷盘数据，按 traceId 去重）。
    public func queryLogsAsync(
        startTime: Int64,
        endTime: Int64,
        isAsc: Bool,
        onSuccess: @escaping ([HttpLogRecord]) -> Void,
        onError: ((Error) -> Void)? = nil
    ) {
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            self.queueLock.lock()
            let pendingSnapshot = self.pendingQueue
            let helper = self.dbHelper
            self.queueLock.unlock()

            let dbRecords = helper.queryRange(startTime: startTime, endTime: endTime, isAsc: isAsc)

            var existingTraceIds = Set<String>(minimumCapacity: dbRecords.count + pendingSnapshot.count)
            for r in dbRecords {
                existingTraceIds.insert(r.traceId)
            }

            var merged = dbRecords
            for pending in pendingSnapshot {
                if pending.timestamp >= startTime && pending.timestamp <= endTime {
                    if !existingTraceIds.contains(pending.traceId) {
                        merged.append(pending)
                        existingTraceIds.insert(pending.traceId)
                    }
                }
            }

            merged.sort { a, b in
                if a.timestamp != b.timestamp {
                    return isAsc ? (a.timestamp < b.timestamp) : (a.timestamp > b.timestamp)
                }
                return isAsc ? (a.id < b.id) : (a.id > b.id)
            }

            DispatchQueue.main.async {
                onSuccess(merged)
            }
        }
    }

    /// 清空指定时间范围内的日志（同步清理内存队列与 SQLite 数据库）。
    public func clearRangeAsync(startTime: Int64, endTime: Int64, onComplete: (() -> Void)? = nil) {
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            self.queueLock.lock()
            self.pendingQueue.removeAll { $0.timestamp >= startTime && $0.timestamp <= endTime }
            let helper = self.dbHelper
            self.queueLock.unlock()

            helper.clearRange(startTime: startTime, endTime: endTime)
            if let onComplete = onComplete {
                DispatchQueue.main.async(execute: onComplete)
            }
        }
    }

    /// 全量清空所有网络日志（同步清理内存队列与 SQLite 数据库）。
    public func clearAllAsync(onComplete: (() -> Void)? = nil) {
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            self.queueLock.lock()
            self.pendingQueue.removeAll()
            let helper = self.dbHelper
            self.queueLock.unlock()

            helper.clearAll()
            if let onComplete = onComplete {
                DispatchQueue.main.async(execute: onComplete)
            }
        }
    }

    /// 同步清空所有网络日志记录。
    public func clearAll() {
        queueLock.lock()
        pendingQueue.removeAll()
        let helper = dbHelper
        queueLock.unlock()
        helper.clearAll()
    }

    /// 关闭定时器并刷盘释放资源。
    public func shutdown() {
        flushTimer?.cancel()
        flushTimer = nil
        flushPendingToDisk()
        dbHelper.closeDatabase()
    }

    /// 异步删除单条网络日志（同步从内存队列和数据库中清除）。
    public func deleteRecordAsync(_ record: HttpLogRecord, onComplete: (() -> Void)? = nil) {
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            self.queueLock.lock()
            self.pendingQueue.removeAll { item in
                (!record.traceId.isEmpty && record.traceId == item.traceId) ||
                (record.id != 0 && record.id == item.id)
            }
            let helper = self.dbHelper
            self.queueLock.unlock()

            helper.deleteRecord(record)
            if let onComplete = onComplete {
                DispatchQueue.main.async(execute: onComplete)
            }
        }
    }

    /// 异步批量删除一组网络日志（同步从内存队列和数据库中清除）。
    public func deleteRecordsBatchAsync(_ records: [HttpLogRecord], onComplete: (() -> Void)? = nil) {
        guard !records.isEmpty else {
            if let onComplete = onComplete {
                DispatchQueue.main.async(execute: onComplete)
            }
            return
        }
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            let traceIds = Set(records.map { $0.traceId }.filter { !$0.isEmpty })
            let ids = Set(records.map { $0.id }.filter { $0 != 0 })

            self.queueLock.lock()
            self.pendingQueue.removeAll { item in
                (!item.traceId.isEmpty && traceIds.contains(item.traceId)) ||
                (item.id != 0 && ids.contains(item.id))
            }
            let helper = self.dbHelper
            self.queueLock.unlock()

            helper.deleteRecordsBatch(records)
            if let onComplete = onComplete {
                DispatchQueue.main.async(execute: onComplete)
            }
        }
    }
}

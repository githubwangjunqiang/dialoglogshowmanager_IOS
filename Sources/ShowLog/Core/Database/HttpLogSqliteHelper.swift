import Foundation
import SQLite3

/// 专用于 HTTP 网络日志持久化的轻量级高性能 SQLite WAL 封装（对齐 Android `HttpLogDbHelper.java`）。
/// 为什么这样做：
/// 1. 直接基于 iOS 系统内置 `libsqlite3` C API 封装，零第三方库依赖；
/// 2. 开启 WAL（Write-Ahead Logging）模式与 `BEGIN IMMEDIATE` 单事务批量提交，彻底杜绝并发读写锁冲突与主线程卡顿；
/// 3. 数据库存放在 `Library/Application Support/ShowLog/showlog_traffic.db`，并标记 `isExcludedFromBackup = true`，避免污染宿主 iCloud 备份。
@objcMembers
public final class HttpLogSqliteHelper: NSObject {

    public static let DATABASE_NAME = "showlog_traffic.db"
    public static let TABLE_NAME = "http_traffic_log"

    private static let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private var db: OpaquePointer?
    private let lock = NSRecursiveLock()
    public let databasePath: String

    public init(customDatabasePath: String? = nil) {
        if let customPath = customDatabasePath, !customPath.isEmpty {
            self.databasePath = customPath
        } else {
            self.databasePath = Self.defaultDatabasePath()
        }
        super.init()
        openAndInitializeDatabase()
    }

    deinit {
        closeDatabase()
    }

    public static func defaultDatabasePath() -> String {
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        var dirURL = appSupportURL.appendingPathComponent("ShowLog", isDirectory: true)
        if !fileManager.fileExists(atPath: dirURL.path) {
            try? fileManager.createDirectory(at: dirURL, withIntermediateDirectories: true, attributes: nil)
        }
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? dirURL.setResourceValues(resourceValues)
        return dirURL.appendingPathComponent(DATABASE_NAME).path
    }

    private func openAndInitializeDatabase() {
        lock.lock()
        defer { lock.unlock() }
        guard db == nil else { return }

        let parentDir = (databasePath as NSString).deletingLastPathComponent
        if !parentDir.isEmpty && !FileManager.default.fileExists(atPath: parentDir) {
            try? FileManager.default.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
        }

        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(databasePath, &db, flags, nil) != SQLITE_OK {
            if let db = db {
                sqlite3_close(db)
            }
            db = nil
            return
        }

        executeRawSQL("PRAGMA journal_mode=WAL;")
        executeRawSQL("PRAGMA synchronous=NORMAL;")

        let createTableSQL = """
        CREATE TABLE IF NOT EXISTS http_traffic_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            trace_id TEXT,
            url TEXT NOT NULL,
            host TEXT NOT NULL,
            path TEXT,
            method TEXT NOT NULL,
            status_code INTEGER NOT NULL,
            success INTEGER DEFAULT 1,
            message TEXT,
            request_headers TEXT,
            request_body TEXT,
            response_headers TEXT,
            response_body TEXT,
            content_type TEXT,
            request_size INTEGER DEFAULT 0,
            response_size INTEGER DEFAULT 0,
            duration_ms INTEGER DEFAULT 0,
            timestamp INTEGER NOT NULL,
            error_message TEXT,
            is_failed INTEGER DEFAULT 0
        );
        CREATE INDEX IF NOT EXISTS idx_traffic_timestamp ON http_traffic_log (timestamp DESC);
        CREATE INDEX IF NOT EXISTS idx_traffic_host ON http_traffic_log (host);
        CREATE INDEX IF NOT EXISTS idx_traffic_path ON http_traffic_log (path);
        CREATE INDEX IF NOT EXISTS idx_traffic_status ON http_traffic_log (status_code);
        CREATE INDEX IF NOT EXISTS idx_traffic_success ON http_traffic_log (success);
        """
        executeRawSQL(createTableSQL)
    }

    public func closeDatabase() {
        lock.lock()
        defer { lock.unlock() }
        if let currentDb = db {
            sqlite3_close_v2(currentDb)
            db = nil
        }
    }

    @discardableResult
    private func executeRawSQL(_ sql: String) -> Bool {
        guard let currentDb = db else { return false }
        var errMsg: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(currentDb, sql, nil, nil, &errMsg)
        if let err = errMsg {
            sqlite3_free(err)
        }
        return rc == SQLITE_OK
    }

    /// 批量插入网络日志记录（使用单事务保障极致性能与原子性）。
    public func insertBatch(_ records: [HttpLogRecord]) {
        guard !records.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        if db == nil { openAndInitializeDatabase() }
        guard let currentDb = db else { return }

        let insertSQL = """
        INSERT INTO http_traffic_log (
            trace_id, url, host, path, method,
            status_code, success, message,
            request_headers, request_body,
            response_headers, response_body,
            content_type, request_size, response_size,
            duration_ms, timestamp, error_message, is_failed
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        guard executeRawSQL("BEGIN IMMEDIATE TRANSACTION;") else { return }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(currentDb, insertSQL, -1, &stmt, nil) == SQLITE_OK,
              let statement = stmt else {
            executeRawSQL("ROLLBACK;")
            return
        }

        var succeeded = true
        for record in records {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)

            bindText(statement, index: 1, value: record.traceId)
            bindText(statement, index: 2, value: record.url)
            bindText(statement, index: 3, value: record.host)
            bindText(statement, index: 4, value: record.path)
            bindText(statement, index: 5, value: record.method)
            sqlite3_bind_int(statement, 6, Int32(record.statusCode))
            sqlite3_bind_int(statement, 7, record.success ? 1 : 0)
            bindText(statement, index: 8, value: record.message)
            bindText(statement, index: 9, value: record.requestHeaders)
            bindText(statement, index: 10, value: record.requestBody)
            bindText(statement, index: 11, value: record.responseHeaders)
            bindText(statement, index: 12, value: record.responseBody)
            bindText(statement, index: 13, value: record.contentType)
            sqlite3_bind_int64(statement, 14, record.requestSize)
            sqlite3_bind_int64(statement, 15, record.responseSize)
            sqlite3_bind_int64(statement, 16, record.durationMs)
            sqlite3_bind_int64(statement, 17, record.timestamp)
            bindText(statement, index: 18, value: record.errorMessage)
            sqlite3_bind_int(statement, 19, record.isFailed ? 1 : 0)

            if sqlite3_step(statement) != SQLITE_DONE {
                succeeded = false
                break
            }
        }

        sqlite3_finalize(statement)
        if succeeded {
            executeRawSQL("COMMIT;")
        } else {
            executeRawSQL("ROLLBACK;")
        }
    }

    /// 根据时间范围查询已持久化的历史网络日志。
    public func queryRange(startTime: Int64, endTime: Int64, isAsc: Bool) -> [HttpLogRecord] {
        lock.lock()
        defer { lock.unlock() }
        if db == nil { openAndInitializeDatabase() }
        guard let currentDb = db else { return [] }

        let order = isAsc ? "ASC" : "DESC"
        let querySQL = """
        SELECT
            id, trace_id, url, host, path, method,
            status_code, success, message,
            request_headers, request_body,
            response_headers, response_body,
            content_type, request_size, response_size,
            duration_ms, timestamp, error_message, is_failed
        FROM http_traffic_log
        WHERE timestamp >= ? AND timestamp <= ?
        ORDER BY timestamp \(order), id \(order);
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(currentDb, querySQL, -1, &stmt, nil) == SQLITE_OK,
              let statement = stmt else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, startTime)
        sqlite3_bind_int64(statement, 2, endTime)

        var result: [HttpLogRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            result.append(parseRow(statement))
        }
        return result
    }

    /// 执行 LRU 容量修剪：仅保留最新的 `maxLimit` 条记录。
    public func trimToLimit(_ maxLimit: Int) {
        guard maxLimit > 0 else { return }
        lock.lock()
        defer { lock.unlock() }
        if db == nil { openAndInitializeDatabase() }
        guard let currentDb = db else { return }

        var countStmt: OpaquePointer?
        var count: Int64 = 0
        if sqlite3_prepare_v2(currentDb, "SELECT count(id) FROM http_traffic_log;", -1, &countStmt, nil) == SQLITE_OK,
           let stmt = countStmt {
            if sqlite3_step(stmt) == SQLITE_ROW {
                count = sqlite3_column_int64(stmt, 0)
            }
            sqlite3_finalize(stmt)
        }

        guard count > Int64(maxLimit) else { return }

        let trimSQL = """
        DELETE FROM http_traffic_log WHERE id NOT IN (
            SELECT id FROM http_traffic_log ORDER BY id DESC LIMIT ?
        );
        """
        var deleteStmt: OpaquePointer?
        if sqlite3_prepare_v2(currentDb, trimSQL, -1, &deleteStmt, nil) == SQLITE_OK,
           let stmt = deleteStmt {
            sqlite3_bind_int(stmt, 1, Int32(maxLimit))
            _ = sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    /// 清空指定时间范围内的全部日志。
    @discardableResult
    public func clearRange(startTime: Int64, endTime: Int64) -> Int {
        lock.lock()
        defer { lock.unlock() }
        if db == nil { openAndInitializeDatabase() }
        guard let currentDb = db else { return 0 }

        let sql = "DELETE FROM http_traffic_log WHERE timestamp >= ? AND timestamp <= ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(currentDb, sql, -1, &stmt, nil) == SQLITE_OK,
              let statement = stmt else {
            return 0
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, startTime)
        sqlite3_bind_int64(statement, 2, endTime)
        if sqlite3_step(statement) == SQLITE_DONE {
            return Int(sqlite3_changes(currentDb))
        }
        return 0
    }

    /// 清空整个数据表中的所有日志。
    public func clearAll() {
        lock.lock()
        defer { lock.unlock() }
        if db == nil { openAndInitializeDatabase() }
        executeRawSQL("DELETE FROM http_traffic_log;")
    }

    /// 删除指定的一条网络日志记录。
    @discardableResult
    public func deleteRecord(_ record: HttpLogRecord) -> Int {
        lock.lock()
        defer { lock.unlock() }
        if db == nil { openAndInitializeDatabase() }
        guard let currentDb = db else { return 0 }

        if !record.traceId.isEmpty {
            let sql = "DELETE FROM http_traffic_log WHERE trace_id = ?;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(currentDb, sql, -1, &stmt, nil) == SQLITE_OK,
               let statement = stmt {
                defer { sqlite3_finalize(statement) }
                bindText(statement, index: 1, value: record.traceId)
                if sqlite3_step(statement) == SQLITE_DONE {
                    return Int(sqlite3_changes(currentDb))
                }
            }
        } else if record.id > 0 {
            let sql = "DELETE FROM http_traffic_log WHERE id = ?;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(currentDb, sql, -1, &stmt, nil) == SQLITE_OK,
               let statement = stmt {
                defer { sqlite3_finalize(statement) }
                sqlite3_bind_int64(statement, 1, record.id)
                if sqlite3_step(statement) == SQLITE_DONE {
                    return Int(sqlite3_changes(currentDb))
                }
            }
        }
        return 0
    }

    /// 批量删除一组网络日志记录（在单事务中执行以提升吞吐量）。
    @discardableResult
    public func deleteRecordsBatch(_ records: [HttpLogRecord]) -> Int {
        guard !records.isEmpty else { return 0 }
        lock.lock()
        defer { lock.unlock() }
        if db == nil { openAndInitializeDatabase() }
        guard let currentDb = db else { return 0 }

        guard executeRawSQL("BEGIN IMMEDIATE TRANSACTION;") else { return 0 }
        var totalDeleted = 0

        let sqlByTrace = "DELETE FROM http_traffic_log WHERE trace_id = ?;"
        let sqlById = "DELETE FROM http_traffic_log WHERE id = ?;"
        var traceStmt: OpaquePointer?
        var idStmt: OpaquePointer?
        _ = sqlite3_prepare_v2(currentDb, sqlByTrace, -1, &traceStmt, nil)
        _ = sqlite3_prepare_v2(currentDb, sqlById, -1, &idStmt, nil)

        for record in records {
            if !record.traceId.isEmpty, let statement = traceStmt {
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
                bindText(statement, index: 1, value: record.traceId)
                if sqlite3_step(statement) == SQLITE_DONE {
                    totalDeleted += Int(sqlite3_changes(currentDb))
                }
            } else if record.id > 0, let statement = idStmt {
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
                sqlite3_bind_int64(statement, 1, record.id)
                if sqlite3_step(statement) == SQLITE_DONE {
                    totalDeleted += Int(sqlite3_changes(currentDb))
                }
            }
        }

        if let s = traceStmt { sqlite3_finalize(s) }
        if let s = idStmt { sqlite3_finalize(s) }
        executeRawSQL("COMMIT;")
        return totalDeleted
    }

    // MARK: - Private Helpers

    private func bindText(_ statement: OpaquePointer, index: Int32, value: String?) {
        guard let value = value else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_text(statement, index, (value as NSString).utf8String, -1, Self.SQLITE_TRANSIENT)
    }

    private func readColumnText(_ statement: OpaquePointer, index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let cStr = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: cStr)
    }

    private func parseRow(_ statement: OpaquePointer) -> HttpLogRecord {
        let id = sqlite3_column_int64(statement, 0)
        let traceId = readColumnText(statement, index: 1) ?? ""
        let url = readColumnText(statement, index: 2) ?? ""
        let host = readColumnText(statement, index: 3) ?? ""
        let path = readColumnText(statement, index: 4) ?? ""
        let method = readColumnText(statement, index: 5) ?? "GET"
        let statusCode = Int(sqlite3_column_int(statement, 6))
        let successInt = sqlite3_column_int(statement, 7)
        let isFailedInt = sqlite3_column_int(statement, 19)
        let success = sqlite3_column_type(statement, 7) != SQLITE_NULL ? (successInt == 1) : (isFailedInt == 0)
        let rawMessage = readColumnText(statement, index: 8)
        let message = (rawMessage?.isEmpty == false ? rawMessage : nil) ?? (success ? "OK" : "FAILED")
        let requestHeaders = readColumnText(statement, index: 9)
        let requestBody = readColumnText(statement, index: 10)
        let responseHeaders = readColumnText(statement, index: 11)
        let responseBody = readColumnText(statement, index: 12)
        let contentType = readColumnText(statement, index: 13)
        let requestSize = sqlite3_column_int64(statement, 14)
        let responseSize = sqlite3_column_int64(statement, 15)
        let durationMs = sqlite3_column_int64(statement, 16)
        let timestamp = sqlite3_column_int64(statement, 17)
        let errorMessage = readColumnText(statement, index: 18)

        return HttpLogRecord.Builder()
            .id(id)
            .traceId(traceId)
            .url(url)
            .host(host)
            .path(path)
            .method(method)
            .statusCode(statusCode)
            .success(success)
            .message(message)
            .requestHeaders(requestHeaders)
            .requestBody(requestBody)
            .responseHeaders(responseHeaders)
            .responseBody(responseBody)
            .contentType(contentType)
            .requestSize(requestSize)
            .responseSize(responseSize)
            .durationMs(durationMs)
            .timestamp(timestamp)
            .errorMessage(errorMessage)
            .isFailed(!success)
            .build()
    }
}

import Foundation
import zlib

/// URLProtocol 自动网络拦截器（对齐 Android `ShowLogOkHttpInterceptor.java`）。
/// 支持 URLSession 及基于 URLSession 的 Alamofire / AFNetworking。
@objcMembers
public final class ShowLogURLProtocol: URLProtocol {

    public static let handledKey = "com.xq.showlog.handled"

    private var internalSession: URLSession?
    private var dataTask: URLSessionDataTask?
    private var startTimeMs: Int64 = 0
    private var receivedResponse: HTTPURLResponse?
    private var capturedResponseData = Data()
    private var totalResponseBytes: Int64 = 0

    // MARK: - URLProtocol Overrides

    public override class func canInit(with request: URLRequest) -> Bool {
        // 1. 生产包零开销直通：关闭状态下首行直接返回 false，0 内存分配、0 流克隆
        guard ShowLog.isEnabled() else {
            return false
        }
        // 2. 防递归拦截检查
        if URLProtocol.property(forKey: handledKey, in: request) != nil {
            return false
        }
        // 3. 仅拦截 http / https 请求
        guard let scheme = request.url?.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }
        // 4. 跳过 WebSocket 升级请求
        if let upgrade = request.value(forHTTPHeaderField: "Upgrade"),
           upgrade.caseInsensitiveCompare("websocket") == .orderedSame {
            return false
        }
        return true
    }

    public override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    public override func startLoading() {
        startTimeMs = HttpLogRecord.currentTimeMillis()
        guard let mutableRequest = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        URLProtocol.setProperty(true, forKey: Self.handledKey, in: mutableRequest)

        let config = URLSessionConfiguration.default
        // 确保内部转发 Session 不包含 ShowLogURLProtocol，彻底杜绝递归循环
        if let existing = config.protocolClasses {
            config.protocolClasses = existing.filter { $0 != ShowLogURLProtocol.self }
        }
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.internalSession = session
        let task = session.dataTask(with: mutableRequest as URLRequest)
        self.dataTask = task
        task.resume()
    }

    public override func stopLoading() {
        dataTask?.cancel()
        dataTask = nil
        internalSession?.invalidateAndCancel()
        internalSession = nil
    }

    // MARK: - Body Extraction & Formatting Helpers

    /// 判断二进制数据前 64 字节是否为可读纯文本（对齐 Android `isPlaintext(Buffer)`）。
    public static func isPlaintext(_ data: Data) -> Bool {
        if data.isEmpty { return true }
        let prefixCount = min(data.count, 64)
        let prefixData = data.prefix(prefixCount)

        // 若包含 0x00 空字节，直接判定为二进制
        if prefixData.contains(0x00) {
            return false
        }

        // 尝试找到有效的 UTF-8 边界（防止第 64 字节刚好截断在多字节 UTF-8 字符中间）
        for trim in 0..<min(4, prefixCount) {
            let slice = prefixData.prefix(prefixCount - trim)
            if let str = String(data: slice, encoding: .utf8) {
                for scalar in str.unicodeScalars {
                    let v = scalar.value
                    let isControl = (v < 0x20 && v != 0x09 && v != 0x0A && v != 0x0D) || (v >= 0x7F && v <= 0x9F)
                    if isControl {
                        return false
                    }
                }
                return true
            }
        }
        return false
    }

    /// 提取请求体文本与总字节数。
    public static func extractRequestBody(from request: URLRequest, maxBodyBytes: Int) -> (body: String?, size: Int64) {
        if let httpBody = request.httpBody {
            let totalSize = Int64(httpBody.count)
            let formatted = decodeAndFormatBody(
                capturedData: httpBody.prefix(maxBodyBytes),
                totalSize: totalSize,
                maxBodyBytes: maxBodyBytes,
                isGzipped: isGzipHeader(request.allHTTPHeaderFields)
            )
            return (formatted, totalSize)
        }

        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var captured = Data()
            var totalSize: Int64 = 0
            let bufferSize = 8192
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { buffer.deallocate() }

            while stream.hasBytesAvailable {
                let readCount = stream.read(buffer, maxLength: bufferSize)
                if readCount > 0 {
                    totalSize += Int64(readCount)
                    if captured.count < maxBodyBytes {
                        let remaining = maxBodyBytes - captured.count
                        captured.append(buffer, count: min(readCount, remaining))
                    }
                } else {
                    break
                }
            }
            let formatted = decodeAndFormatBody(
                capturedData: captured,
                totalSize: totalSize,
                maxBodyBytes: maxBodyBytes,
                isGzipped: isGzipHeader(request.allHTTPHeaderFields)
            )
            return (formatted, totalSize)
        }

        return (nil, 0)
    }

    /// 安全解码并格式化请求/响应体（支持 gzip 解压、二进制探测、超长截断与 JSON 2 空格美化）。
    public static func decodeAndFormatBody(
        capturedData: Data,
        totalSize: Int64,
        maxBodyBytes: Int,
        isGzipped: Bool
    ) -> String? {
        if totalSize == 0 && capturedData.isEmpty {
            return ""
        }

        var workingData = Data(capturedData)
        // 检查 gzip 魔数 (0x1f 0x8b)
        if workingData.count >= 2 {
            let first = workingData[workingData.startIndex]
            let second = workingData[workingData.index(after: workingData.startIndex)]
            if (isGzipped || (first == 0x1f && second == 0x8b)),
               let decompressed = gunzip(workingData, maxOutputBytes: maxBodyBytes) {
                workingData = decompressed
            }
        }

        guard isPlaintext(workingData) else {
            return "[Binary Data: size=\(totalSize) bytes]"
        }

        // 处理截断时可能切碎尾部 UTF-8 字符的情况
        var decodedString: String?
        for trim in 0..<min(4, workingData.count) {
            let slice = workingData.prefix(workingData.count - trim)
            if let str = String(data: slice, encoding: .utf8) {
                decodedString = str
                break
            }
        }

        guard var text = decodedString else {
            return "[Binary Data: size=\(totalSize) bytes]"
        }

        let isTruncated = totalSize > Int64(maxBodyBytes) || workingData.count > maxBodyBytes
        if isTruncated {
            text += "\n\n... [Content truncated: Total \(totalSize) bytes, preserved first \(maxBodyBytes) bytes] ..."
            return text
        }

        return JsonFormatter.formatJsonString(text)
    }

    public static func isGzipHeader(_ headers: [AnyHashable: Any]?) -> Bool {
        guard let headers = headers else { return false }
        for (k, v) in headers {
            if let key = k as? String,
               key.caseInsensitiveCompare("Content-Encoding") == .orderedSame,
               let val = v as? String,
               val.lowercased().contains("gzip") {
                return true
            }
        }
        return false
    }

    /// 使用系统 zlib 安全解压 gzip 数据，限制最大输出字节防止 zip 炸弹。
    public static func gunzip(_ data: Data, maxOutputBytes: Int) -> Data? {
        guard data.count > 2 else { return nil }
        var stream = z_stream()
        let initStatus: Int32 = data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.bindMemory(to: Bytef.self).baseAddress else {
                return Z_DATA_ERROR
            }
            stream.next_in = UnsafeMutablePointer<Bytef>(mutating: baseAddress)
            stream.avail_in = uInt(data.count)
            return inflateInit2_(&stream, 15 + 32, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        }
        guard initStatus == Z_OK else { return nil }
        defer { inflateEnd(&stream) }

        var output = Data()
        let chunkSize = 16384
        var buffer = [UInt8](repeating: 0, count: chunkSize)
        let capLimit = max(maxOutputBytes, 1024)

        var status: Int32 = Z_OK
        while status == Z_OK {
            let produced: Int = buffer.withUnsafeMutableBufferPointer { bufPtr in
                stream.next_out = bufPtr.baseAddress
                stream.avail_out = uInt(chunkSize)
                status = inflate(&stream, Z_SYNC_FLUSH)
                return chunkSize - Int(stream.avail_out)
            }
            if produced > 0 {
                let allowed = min(produced, capLimit - output.count)
                if allowed > 0 {
                    output.append(buffer, count: allowed)
                }
                if output.count >= capLimit {
                    break
                }
            }
            if status == Z_STREAM_END {
                break
            } else if status != Z_OK {
                return output.isEmpty ? nil : output
            }
        }
        return output
    }

    private func recordCompletedTransaction(error: Error?) {
        guard ShowLog.isEnabled() else { return }

        let config = ShowLog.getConfig()
        let maxBytes = config.maxBodyBytes
        let duration = max(0, HttpLogRecord.currentTimeMillis() - startTimeMs)
        let urlStr = request.url?.absoluteString ?? ""
        let (host, path) = HttpLogRecord.extractHostAndPath(from: urlStr)
        let method = request.httpMethod?.uppercased() ?? "GET"

        let reqHeaderDict = request.allHTTPHeaderFields
        let reqHeadersStr = HttpLogRecord.formatHeaders(reqHeaderDict, config: config)
        let (reqBodyStr, reqSize) = Self.extractRequestBody(from: request, maxBodyBytes: maxBytes)

        var resHeaderDict: [String: String]?
        if let allFields = receivedResponse?.allHeaderFields {
            var dict: [String: String] = [:]
            for (k, v) in allFields {
                dict[String(describing: k)] = String(describing: v)
            }
            resHeaderDict = dict
        }
        let resHeadersStr = HttpLogRecord.formatHeaders(resHeaderDict, config: config)
        let contentType = receivedResponse?.mimeType
            ?? HttpLogRecord.extractContentType(from: resHeaderDict)
            ?? HttpLogRecord.extractContentType(from: reqHeaderDict)

        if let error = error {
            let nsErr = error as NSError
            var isSuccess = false
            var businessMsg = nsErr.localizedDescription.isEmpty ? "Network Error" : nsErr.localizedDescription
            let fullErrorDesc = "\(nsErr.domain) (code: \(nsErr.code)): \(nsErr.localizedDescription)\n\(String(describing: error))"

            if let judger = ShowLog.getBusinessJudger() {
                let ctx = HttpLogRequestContext(
                    url: urlStr,
                    host: host,
                    path: path,
                    method: method,
                    httpCode: -1,
                    durationMs: duration,
                    requestHeaders: reqHeaderDict,
                    responseHeaders: resHeaderDict,
                    requestBody: reqBodyStr,
                    responseBody: nil,
                    error: error
                )
                let res = judger.judge(ctx)
                isSuccess = res.isSuccess()
                if !res.getMessage().isEmpty {
                    businessMsg = res.getMessage()
                }
            }

            let record = HttpLogRecord.Builder()
                .url(urlStr)
                .host(host)
                .path(path)
                .method(method)
                .statusCode(-1)
                .httpCode(-1)
                .success(isSuccess)
                .message(businessMsg)
                .requestHeaders(reqHeadersStr)
                .requestBody(reqBodyStr)
                .responseHeaders(resHeadersStr)
                .contentType(contentType)
                .requestSize(reqSize)
                .responseSize(0)
                .durationMs(duration)
                .timestamp(startTimeMs)
                .errorMessage(fullErrorDesc)
                .isFailed(!isSuccess)
                .build()
            HttpLogRepository.shared.enqueueLog(record)
            return
        }

        let statusCode = receivedResponse?.statusCode ?? 200
        let isGzipped = Self.isGzipHeader(receivedResponse?.allHeaderFields)
        let resBodyStr = Self.decodeAndFormatBody(
            capturedData: capturedResponseData,
            totalSize: totalResponseBytes,
            maxBodyBytes: maxBytes,
            isGzipped: isGzipped
        )

        var isSuccess = (200..<300).contains(statusCode)
        var businessMsg = isSuccess ? "OK" : "HTTP \(statusCode)"

        if let judger = ShowLog.getBusinessJudger() {
            let ctx = HttpLogRequestContext(
                url: urlStr,
                host: host,
                path: path,
                method: method,
                httpCode: statusCode,
                durationMs: duration,
                requestHeaders: reqHeaderDict,
                responseHeaders: resHeaderDict,
                requestBody: reqBodyStr,
                responseBody: resBodyStr,
                error: nil
            )
            let res = judger.judge(ctx)
            isSuccess = res.isSuccess()
            if !res.getMessage().isEmpty {
                businessMsg = res.getMessage()
            }
        }

        let errorMsg: String? = isSuccess ? nil : businessMsg

        let record = HttpLogRecord.Builder()
            .url(urlStr)
            .host(host)
            .path(path)
            .method(method)
            .statusCode(statusCode)
            .httpCode(statusCode)
            .success(isSuccess)
            .message(businessMsg)
            .requestHeaders(reqHeadersStr)
            .requestBody(reqBodyStr)
            .responseHeaders(resHeadersStr)
            .responseBody(resBodyStr)
            .contentType(contentType)
            .requestSize(reqSize)
            .responseSize(totalResponseBytes)
            .durationMs(duration)
            .timestamp(startTimeMs)
            .errorMessage(errorMsg)
            .isFailed(!isSuccess)
            .build()

        HttpLogRepository.shared.enqueueLog(record)
    }
}

// MARK: - URLSessionDataDelegate & URLSessionTaskDelegate

extension ShowLogURLProtocol: URLSessionDataDelegate, URLSessionTaskDelegate {

    public func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        self.receivedResponse = response as? HTTPURLResponse
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        completionHandler(.allow)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        // 1. 第一时间原样转发给宿主，保证宿主响应流 100% 完整且零延迟
        client?.urlProtocol(self, didLoad: data)

        // 2. 累加实际字节数，且仅在未超出 maxBodyBytes 时追加采集缓冲，彻底杜绝大文件下载 OOM
        totalResponseBytes += Int64(data.count)
        let maxBytes = ShowLog.getConfig().maxBodyBytes
        if capturedResponseData.count < maxBytes {
            let remaining = maxBytes - capturedResponseData.count
            capturedResponseData.append(data.prefix(remaining))
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        recordCompletedTransaction(error: error)
        if let error = error {
            client?.urlProtocol(self, didFailWithError: error)
        } else {
            client?.urlProtocolDidFinishLoading(self)
        }
        session.finishTasksAndInvalidate()
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        if let mutableReq = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest {
            URLProtocol.removeProperty(forKey: Self.handledKey, in: mutableReq)
            client?.urlProtocol(self, wasRedirectedTo: mutableReq as URLRequest, redirectResponse: response)
            completionHandler(mutableReq as URLRequest)
        } else {
            client?.urlProtocol(self, wasRedirectedTo: request, redirectResponse: response)
            completionHandler(request)
        }
    }

    public func urlSession(
        _ session: URLSession,
         task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        completionHandler(.performDefaultHandling, nil)
    }
}

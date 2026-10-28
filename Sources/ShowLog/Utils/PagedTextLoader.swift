import Foundation
import ImageIO

/// 文件预览类型枚举。
@objc public enum ShowLogFilePreviewKind: Int {
    case text = 0
    case image = 1
    case unsupported = 2
}

/// 单页文本读取结果。
@objcMembers
public final class TextPageData: NSObject {
    public let text: String
    public let nextByteOffset: UInt64
    public let hasMore: Bool

    public init(text: String, nextByteOffset: UInt64, hasMore: Bool) {
        self.text = text
        self.nextByteOffset = nextByteOffset
        self.hasMore = hasMore
        super.init()
    }
}

/// 32KB 分块流式文本读取、UTF-8/UTF-16 BOM 编码探测与防路径穿越校验工具（对齐 Android `FileBrowserView` & `PagedTextLoader`）。
@objcMembers
public final class PagedTextLoader: NSObject {

    public static let DEFAULT_PAGE_BYTES: Int = 32 * 1024

    /// 校验目标路径是否严格位于允许的根目录之内（解析符号链接与 `..`，防御 Path Traversal 攻击）。
    public static func isWithinRoot(rootPath: String, candidatePath: String) -> Bool {
        let trimmedRoot = rootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCandidate = candidatePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRoot.isEmpty, !trimmedCandidate.isEmpty else { return false }

        let rootURL = URL(fileURLWithPath: trimmedRoot).resolvingSymlinksInPath().standardizedFileURL
        let targetURL = URL(fileURLWithPath: trimmedCandidate).resolvingSymlinksInPath().standardizedFileURL

        let canonicalRoot = rootURL.path
        let canonicalTarget = targetURL.path

        if canonicalTarget == canonicalRoot {
            return true
        }
        let prefix = canonicalRoot.hasSuffix("/") ? canonicalRoot : (canonicalRoot + "/")
        return canonicalTarget.hasPrefix(prefix)
    }

    /// 探测文件预览类型（TEXT / IMAGE / UNSUPPORTED）。
    public static func detectPreviewKind(rootPath: String, filePath: String) -> ShowLogFilePreviewKind {
        guard isWithinRoot(rootPath: rootPath, candidatePath: filePath) else {
            return .unsupported
        }
        var isDir: ObjCBool = false
        let fm = FileManager.default
        guard fm.fileExists(atPath: filePath, isDirectory: &isDir),
              !isDir.boolValue,
              fm.isReadableFile(atPath: filePath) else {
            return .unsupported
        }

        let ext = (filePath as NSString).pathExtension.lowercased()
        if ext == "pdf" || ext == "sqlite" || ext == "db" || ext == "dylib" || ext == "so" || ext == "zip" {
            return .unsupported
        }

        let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "bmp", "heic", "heif", "tiff", "ico"]
        if imageExtensions.contains(ext) {
            return .image
        }

        let textExtensions: Set<String> = [
            "txt", "log", "json", "xml", "html", "htm", "css", "js", "ts",
            "md", "csv", "yaml", "yml", "ini", "conf", "plist", "swift", "m", "h", "c", "cpp", "java", "py", "sh"
        ]

        guard let handle = FileHandle(forReadingAtPath: filePath) else {
            return .unsupported
        }
        defer {
            if #available(iOS 13.0, macOS 10.15, *) {
                try? handle.close()
            } else {
                handle.closeFile()
            }
        }

        let sample = handle.readData(ofLength: 4096)
        if sample.isEmpty {
            return .text
        }

        // PDF 魔数 "%PDF-"
        if sample.count >= 5,
           sample[0] == 0x25, sample[1] == 0x50, sample[2] == 0x44, sample[3] == 0x46, sample[4] == 0x2D {
            return .unsupported
        }

        // SQLite 3 魔数 "SQLite format 3\0"
        if sample.count >= 16,
           let headerStr = String(data: sample.prefix(15), encoding: .ascii),
           headerStr == "SQLite format 3" {
            return .unsupported
        }

        // UTF-8 BOM (EF BB BF) 或 UTF-16 LE/BE BOM (FF FE / FE FF)
        if sample.count >= 3, sample[0] == 0xEF, sample[1] == 0xBB, sample[2] == 0xBF {
            return .text
        }
        if sample.count >= 2,
           (sample[0] == 0xFF && sample[1] == 0xFE) || (sample[0] == 0xFE && sample[1] == 0xFF) {
            return .text
        }

        // ImageIO 图像头探测（针对无扩展名图片）
        if !textExtensions.contains(ext),
           let source = CGImageSourceCreateWithData(sample as CFData, nil),
           CGImageSourceGetCount(source) > 0 {
            return .image
        }

        // 嗅探是否包含空字节或非法控制字符
        for byte in sample {
            if byte == 0x00 {
                return .unsupported
            }
            if byte < 0x09 || (byte > 0x0D && byte < 0x20) {
                return .unsupported
            }
        }

        return .text
    }

    /// 按字节偏移量分页读取文本文件（默认每页 32KB，自动处理 UTF-8 / UTF-16 BOM 及多字节字符边界）。
    public static func readTextPage(
        rootPath: String,
        filePath: String,
        byteOffset: UInt64,
        maxBytes: Int = DEFAULT_PAGE_BYTES
    ) -> TextPageData? {
        guard isWithinRoot(rootPath: rootPath, candidatePath: filePath),
              let handle = FileHandle(forReadingAtPath: filePath) else {
            return nil
        }
        defer {
            if #available(iOS 13.0, macOS 10.15, *) {
                try? handle.close()
            } else {
                handle.closeFile()
            }
        }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: filePath)[.size] as? NSNumber)?.uint64Value ?? 0
        if fileSize == 0 {
            return TextPageData(text: "", nextByteOffset: 0, hasMore: false)
        }

        // 探测文件头 BOM 编码
        handle.seek(toFileOffset: 0)
        let bomSample = handle.readData(ofLength: 3)
        var encoding: String.Encoding = .utf8
        var bomSkip: UInt64 = 0
        if bomSample.count >= 3 && bomSample[0] == 0xEF && bomSample[1] == 0xBB && bomSample[2] == 0xBF {
            encoding = .utf8
            bomSkip = 3
        } else if bomSample.count >= 2 && bomSample[0] == 0xFF && bomSample[1] == 0xFE {
            encoding = .utf16LittleEndian
            bomSkip = 2
        } else if bomSample.count >= 2 && bomSample[0] == 0xFE && bomSample[1] == 0xFF {
            encoding = .utf16BigEndian
            bomSkip = 2
        }

        let effectiveOffset = max(byteOffset, bomSkip)
        guard effectiveOffset < fileSize else {
            return TextPageData(text: "", nextByteOffset: fileSize, hasMore: false)
        }

        handle.seek(toFileOffset: effectiveOffset)
        let pageLimit = max(1024, maxBytes)
        let rawChunk = handle.readData(ofLength: pageLimit)
        if rawChunk.isEmpty {
            return TextPageData(text: "", nextByteOffset: fileSize, hasMore: false)
        }

        if encoding == .utf16LittleEndian || encoding == .utf16BigEndian {
            let evenLength = rawChunk.count - (rawChunk.count % 2)
            let slice = rawChunk.prefix(evenLength)
            let text = String(data: slice, encoding: encoding) ?? String(decoding: slice, as: UTF8.self)
            let nextOffset = effectiveOffset + UInt64(slice.count)
            return TextPageData(text: text, nextByteOffset: nextOffset, hasMore: nextOffset < fileSize)
        }

        // UTF-8：防止分块末尾刚好截断多字节字符，最多回退 3 个字节对齐完整 UTF-8 序列
        for trim in 0..<min(4, rawChunk.count) {
            let validCount = rawChunk.count - trim
            let slice = rawChunk.prefix(validCount)
            if let str = String(data: slice, encoding: .utf8) {
                let nextOffset = effectiveOffset + UInt64(validCount)
                return TextPageData(text: str, nextByteOffset: nextOffset, hasMore: nextOffset < fileSize)
            }
        }

        let fallback = String(decoding: rawChunk, as: UTF8.self)
        let nextOffset = effectiveOffset + UInt64(rawChunk.count)
        return TextPageData(text: fallback, nextByteOffset: nextOffset, hasMore: nextOffset < fileSize)
    }
}

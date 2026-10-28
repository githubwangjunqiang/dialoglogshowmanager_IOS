import Foundation

/// 安全 JSON 2 空格美化缩进与序列化工具。
/// 为什么这样做：
/// 1. 严格对标 Android `JSONObject.toString(2)` 的 2 空格缩进视觉效果；
/// 2. 在调用 `JSONSerialization.data(withJSONObject:)` 前强制执行 `JSONSerialization.isValidJSONObject` 预检，
///    彻底杜绝因宿主传入非标准 JSON 对象而触发 Objective-C `NSInvalidArgumentException` 导致崩溃。
@objcMembers
public final class JsonFormatter: NSObject {

    private override init() {
        super.init()
    }

    /// 将任意请求/响应载荷安全格式化为美化后的文本字符串。
    /// 支持输入：`String`、`Data`、`[String: Any]`、`[Any]`、`NSNumber` 或其他对象。
    public static func formatAny(_ value: Any?) -> String? {
        guard let value = value else { return nil }
        if value is NSNull { return nil }

        if let str = value as? String {
            return formatJsonString(str)
        }

        if let data = value as? Data {
            if data.isEmpty { return "" }
            if let str = String(data: data, encoding: .utf8) {
                return formatJsonString(str)
            }
            return "[Binary Data: size=\(data.count) bytes]"
        }

        if JSONSerialization.isValidJSONObject(value) {
            if let jsonData = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]),
               let jsonStr = String(data: jsonData, encoding: .utf8) {
                return prettyPrintJsonData(jsonData) ?? jsonStr
            }
        }

        return String(describing: value)
    }

    /// 尝试将原始字符串按 2 空格缩进美化；若非合法 JSON 则原样返回。
    public static func formatJsonString(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) ||
              (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")) else {
            return raw
        }
        guard let data = trimmed.data(using: .utf8),
              let pretty = prettyPrintJsonData(data) else {
            return raw
        }
        return pretty
    }

    /// 使用 2 空格缩进美化 JSON Data。
    private static func prettyPrintJsonData(_ data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              JSONSerialization.isValidJSONObject(obj) else {
            return nil
        }
        var options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys]
        if #available(iOS 13.0, macOS 10.15, *) {
            options.insert(.withoutEscapingSlashes)
        }
        guard let prettyData = try? JSONSerialization.data(withJSONObject: obj, options: options),
              let prettyString = String(data: prettyData, encoding: .utf8) else {
            return nil
        }
        // Apple JSONSerialization.prettyPrinted 默认使用 2 或 4 空格，统一规整为 2 空格缩进
        return normalizeIndentationToTwoSpaces(prettyString)
    }

    private static func normalizeIndentationToTwoSpaces(_ json: String) -> String {
        let lines = json.components(separatedBy: "\n")
        // 检测首个缩进行是 4 空格还是 2 空格
        var usesFourSpaces = false
        for line in lines {
            let leadingSpaces = line.prefix(while: { $0 == " " }).count
            if leadingSpaces > 0 {
                usesFourSpaces = (leadingSpaces % 4 == 0 && leadingSpaces >= 4)
                break
            }
        }
        guard usesFourSpaces else { return json }
        return lines.map { line -> String in
            let leadingSpaces = line.prefix(while: { $0 == " " }).count
            if leadingSpaces >= 4 {
                let newSpaces = String(repeating: " ", count: leadingSpaces / 2)
                return newSpaces + line.dropFirst(leadingSpaces)
            }
            return line
        }.joined(separator: "\n")
    }
}

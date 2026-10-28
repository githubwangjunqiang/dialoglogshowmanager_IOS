import Foundation

/// 诊断报告 Markdown 导出格式化器（严格对齐 Android `AppDeviceInfoExporter.java`）。
/// 为什么这样做：
/// 结构化生成规范的 Markdown 表格文本，方便测试与研发一键复制或分享并直接粘贴到 Bug 提报单中。
@objcMembers
public final class AppDeviceInfoExporter: NSObject {

    private override init() {
        super.init()
    }

    public static func exportToMarkdown(_ info: AppDeviceInfo) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        var sb = ""
        sb += "# 📱 应用与设备系统全景诊断报告\n"
        sb += "> **生成时间**：\(formatter.string(from: Date()))\n\n"

        appendCategorySection(
            to: &sb,
            title: "📦 1. 应用画像 (App Profile)",
            items: info.getItemsByCategory(AppDeviceInfo.CATEGORY_APP)
        )
        appendCategorySection(
            to: &sb,
            title: "🤖 2. 操作系统 (OS & Runtime)",
            items: info.getItemsByCategory(AppDeviceInfo.CATEGORY_OS)
        )
        appendCategorySection(
            to: &sb,
            title: "💻 3. 硬件与显示 (Hardware & Display)",
            items: info.getItemsByCategory(AppDeviceInfo.CATEGORY_HARDWARE)
        )
        appendCategorySection(
            to: &sb,
            title: "⚡ 4. 运行性能 (Runtime Performance)",
            items: info.getItemsByCategory(AppDeviceInfo.CATEGORY_PERFORMANCE)
        )

        sb += "---\n"
        sb += "*Generated automatically by ShowLog SDK.*"
        return sb
    }

    private static func appendCategorySection(
        to sb: inout String,
        title: String,
        items: [AppDeviceInfo.InfoItem]
    ) {
        guard !items.isEmpty else { return }
        sb += "### \(title)\n\n"
        sb += "| 属性名称 | 参数值 |\n"
        sb += "| :--- | :--- |\n"
        for item in items {
            let safeValue = item.value
                .replacingOccurrences(of: "|", with: "\\|")
                .replacingOccurrences(of: "\n", with: " ")
            sb += "| **\(item.key)** | `\(safeValue)` |\n"
        }
        sb += "\n"
    }
}

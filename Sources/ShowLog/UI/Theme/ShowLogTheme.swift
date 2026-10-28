import Foundation
#if canImport(UIKit)
import UIKit

/// 1:1 复刻 Android `res/values/colors.xml` 暗黑配色色板、字号、圆角与 350ms 全局点击防抖工具。
@objcMembers
public final class ShowLogTheme: NSObject {

    /// 顶层深色背景 / 代码块底色 `#121214`
    public static let bgPrimary = color(hex: 0x121214)

    /// 主中枢（Hub）页签与内容面板一体化填充底色 `#1A1A1E`
    public static let bgSurface = color(hex: 0x1A1A1E)

    /// 列表项卡片、工具栏块背景色 `#222228`
    public static let bgCard = color(hex: 0x222228)

    /// 主中枢一体化外轮廓描边（1pt）、卡片分割描边 `#33333D`
    public static let bgCardStroke = color(hex: 0x33333D)

    /// 胶囊按钮、未选中滑块槽背景色 `#2C2C36`
    public static let bgPill = color(hex: 0x2C2C36)

    /// 选中态高亮蓝（主 Tab 选中文字色、滑动开关滑块底色）`#3B82F6`
    public static let bgPillSelected = color(hex: 0x3B82F6)

    /// 一级主标题、正文、URL 文字颜色 `#F4F4F5`
    public static let textPrimary = color(hex: 0xF4F4F5)

    /// 二级副标题、时间戳、未选中标签文字颜色 `#A1A1AA`
    public static let textSecondary = color(hex: 0xA1A1AA)

    /// 三级辅助说明、空状态提示、未选中详情子 Tab 颜色 `#71717A`
    public static let textTertiary = color(hex: 0x71717A)

    /// HTTP 请求方式（GET/POST 等）天蓝色高亮 `#38BDF8`
    public static let textMethod = color(hex: 0x38BDF8)

    /// 业务成功（success == true）及 2xx 状态绿色 `#22C55E`
    public static let status2xx = color(hex: 0x22C55E)

    /// 3xx 重定向状态蓝色 `#3B82F6`
    public static let status3xx = color(hex: 0x3B82F6)

    /// 4xx 客户端错误琥珀黄 `#F59E0B`
    public static let status4xx = color(hex: 0xF59E0B)

    /// 业务失败（success == false）列表项及 5xx 红色 `#EF4444`
    public static let status5xx = color(hex: 0xEF4444)

    /// 详情页 FAIL 状态、Error Tab 警示深红、右上角关闭挂钩红 `#DC2626`
    public static let statusError = color(hex: 0xDC2626)

    /// 操作按钮强调色 `#0EA5E9`
    public static let actionBtn = color(hex: 0x0EA5E9)

    /// 蓝色滑块（#3B82F6）之上的选中文字深色 `#0F172A`
    public static let textOnAccent = color(hex: 0x0F172A)

    /// 全局防抖阈值（350ms）
    public static let throttleMs: Int64 = 350

    public static func color(hex: UInt32, alpha: CGFloat = 1.0) -> UIColor {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8) & 0xFF) / 255.0
        let b = CGFloat(hex & 0xFF) / 255.0
        return UIColor(red: r, green: g, blue: b, alpha: alpha)
    }

    public static func monospacedFont(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        if #available(iOS 13.0, *) {
            return UIFont.monospacedSystemFont(ofSize: size, weight: weight)
        }
        return UIFont(name: "Menlo", size: size) ?? UIFont.systemFont(ofSize: size, weight: weight)
    }
}

/// 350ms 动作防抖节流器。
@objcMembers
public final class ClickThrottler: NSObject {
    private var lastClickTimeMs: Int64 = 0
    private let intervalMs: Int64

    public init(intervalMs: Int64 = 350) {
        self.intervalMs = intervalMs
        super.init()
    }

    /// 若距离上次触发不足 `intervalMs` 返回 `true`（应拦截忽略），否则更新时间并返回 `false`。
    public func isThrottled() -> Bool {
        let now = Int64(ProcessInfo.processInfo.systemUptime * 1000.0)
        if lastClickTimeMs != 0 && (now - lastClickTimeMs) < intervalMs {
            return true
        }
        lastClickTimeMs = now
        return false
    }
}
#endif

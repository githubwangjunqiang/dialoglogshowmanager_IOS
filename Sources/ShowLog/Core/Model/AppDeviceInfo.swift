import Foundation

/// 设备与应用系统全景信息聚合实体（对齐 Android `AppDeviceInfo.java`）。
@objcMembers
public final class AppDeviceInfo: NSObject {

    public static let CATEGORY_APP = "应用画像"
    public static let CATEGORY_OS = "操作系统"
    public static let CATEGORY_HARDWARE = "硬件屏幕"
    public static let CATEGORY_PERFORMANCE = "运行性能"

    /// 单个展示属性条目。
    @objc(AppDeviceInfoItem)
    @objcMembers
    public final class InfoItem: NSObject {
        public let category: String
        public let key: String
        public let value: String
        public let isImportant: Bool

        public init(category: String, key: String, value: String, isImportant: Bool = false) {
            self.category = category
            self.key = key
            self.value = value
            self.isImportant = isImportant
            super.init()
        }
    }

    public let allItems: [InfoItem]

    public init(items: [InfoItem]) {
        self.allItems = items
        super.init()
    }

    /// 获取指定分类下的全部条目（传入 nil、空串或 "全部" 时返回全部条目）。
    public func getItemsByCategory(_ category: String?) -> [InfoItem] {
        guard let category = category, !category.isEmpty, category != "全部" else {
            return allItems
        }
        return allItems.filter { $0.category == category }
    }
}

import Foundation
import CoreData

extension ScheduleItem {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<ScheduleItem> {
        return NSFetchRequest<ScheduleItem>(entityName: "ScheduleItem")
    }

    /// 存储层 id（保持与模型 optional 一致，2026-10-15 崩溃修复）。
    /// 读取请用 `id` 计算属性（nil 兜底）；写入请用本属性（`obj.storageId = UUID()`）。
    @NSManaged @objc(id) public var storageId: UUID?
    @NSManaged public var title: String
    @NSManaged public var startDate: Date
    @NSManaged public var endDate: Date?
    @NSManaged public var isAllDay: Bool
    @NSManaged public var location: String?
    @NSManaged public var notes: String?
    @NSManaged public var colorHex: String?
    @NSManaged public var createdAt: Date
    @NSManaged public var updatedAt: Date

    // MARK: - 提醒相关字段
    @NSManaged public var category: String
    @NSManaged public var repeatRule: String?
    @NSManaged public var reminderEnabled: Bool
    @NSManaged public var reminderLeadMinutes: Int32

    @NSManaged public var task: Task?
}

extension ScheduleItem: Identifiable {
    /// 永不 trap 的对外 id（2026-10-15）：存储缺失（异常数据）时返回固定占位值，
    /// 避免 NSManaged 非 optional 桥接 nil 触发 EXC_BREAKPOINT（实机崩溃实锤）。
    public var id: UUID { storageId ?? Self.missingIdPlaceholder }

    private static let missingIdPlaceholder = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0,
                                                          0, 0, 0, 0, 0, 0, 0, 0))
}

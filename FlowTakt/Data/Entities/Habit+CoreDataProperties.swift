import Foundation
import CoreData

extension Habit {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Habit> {
        return NSFetchRequest<Habit>(entityName: "Habit")
    }

    /// 存储层 id（保持与模型 optional 一致，2026-10-15 崩溃修复）。
    /// 读取请用 `id` 计算属性（nil 兜底）；写入请用本属性（`obj.storageId = UUID()`）。
    @NSManaged @objc(id) public var storageId: UUID?
    @NSManaged public var name: String
    @NSManaged public var descriptionText: String?
    @NSManaged public var iconName: String?
    @NSManaged public var colorHex: String?
    @NSManaged public var frequency: String
    @NSManaged public var targetCount: Int16
    @NSManaged public var currentStreak: Int16
    @NSManaged public var longestStreak: Int16
    @NSManaged public var createdAt: Date
    @NSManaged public var updatedAt: Date

    @NSManaged public var records: Set<HabitRecord>
}

// MARK: - Generated accessors for records
extension Habit {

    @objc(addRecordsObject:)
    @NSManaged public func addToRecords(_ value: HabitRecord)

    @objc(removeRecordsObject:)
    @NSManaged public func removeFromRecords(_ value: HabitRecord)

    @objc(addRecords:)
    @NSManaged public func addToRecords(_ values: Set<HabitRecord>)

    @objc(removeRecords:)
    @NSManaged public func removeFromRecords(_ values: Set<HabitRecord>)
}

extension Habit: Identifiable {
    /// 永不 trap 的对外 id（2026-10-15）：存储缺失（异常数据）时返回固定占位值，
    /// 避免 NSManaged 非 optional 桥接 nil 触发 EXC_BREAKPOINT（实机崩溃实锤）。
    public var id: UUID { storageId ?? Self.missingIdPlaceholder }

    private static let missingIdPlaceholder = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0,
                                                          0, 0, 0, 0, 0, 0, 0, 0))
}

import Foundation
import CoreData

extension HabitRecord {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<HabitRecord> {
        let request = NSFetchRequest<HabitRecord>(entityName: "HabitRecord")
        // 日志型实体数据增长后内存飙升风险，设置 fetchBatchSize 启用分批加载
        request.fetchBatchSize = 50
        return request
    }

    @NSManaged public var id: UUID
    @NSManaged public var date: Date
    @NSManaged public var count: Int16
    @NSManaged public var note: String?
    @NSManaged public var createdAt: Date

    /// 关联的习惯。**刻意保持可选**：模型中该关系原为 `optional="NO"`，
    /// 但 `NSPersistentCloudKitContainer` 不支持级联删除 —— 另一设备删除 Habit 后，
    /// 对应 HabitRecord 的 CKRecord 会残留在 CloudKit，合并后本地即产生 `nil` 关系。
    /// 非可选属性在此时解引用会触发 `EXC_BAD_ACCESS`（Unexpectedly found nil）。
    /// 所有读取点必须使用可选链。
    @NSManaged public var habit: Habit?
}

extension HabitRecord: Identifiable {

}

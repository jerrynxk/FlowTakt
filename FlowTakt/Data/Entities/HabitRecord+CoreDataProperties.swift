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

    @NSManaged public var habit: Habit
}

extension HabitRecord: Identifiable {

}

import Foundation
import CoreData

extension FocusSession {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<FocusSession> {
        let request = NSFetchRequest<FocusSession>(entityName: "FocusSession")
        // 日志型实体数据增长后内存飙升风险，设置 fetchBatchSize 启用分批加载
        request.fetchBatchSize = 50
        return request
    }

    @NSManaged public var id: UUID
    @NSManaged public var startTime: Date
    @NSManaged public var endTime: Date?
    @NSManaged public var plannedDuration: Double
    @NSManaged public var actualDuration: Double
    @NSManaged public var phase: String
    @NSManaged public var roundIndex: Int16
    @NSManaged public var status: String
    @NSManaged public var earnedPoints: Int16
    @NSManaged public var createdAt: Date
    @NSManaged public var updatedAt: Date

    @NSManaged public var task: Task?
    @NSManaged public var tag: Tag?
}

extension FocusSession: Identifiable {

}

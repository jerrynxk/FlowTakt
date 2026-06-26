import Foundation
import CoreData

extension Tag {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Tag> {
        return NSFetchRequest<Tag>(entityName: "Tag")
    }

    @NSManaged public var id: UUID
    @NSManaged public var name: String
    @NSManaged public var colorHex: String?
    @NSManaged public var createdAt: Date

    @NSManaged public var tasks: Set<Task>
    @NSManaged public var sessions: Set<FocusSession>
    /// 标签关联的时间记录（与数据模型 .xcdatamodel 中定义的 timeRecords 关系对应）
    @NSManaged public var timeRecords: Set<TimeRecord>
}

// MARK: - Generated accessors for tasks
extension Tag {

    @objc(addTasksObject:)
    @NSManaged public func addToTasks(_ value: Task)

    @objc(removeTasksObject:)
    @NSManaged public func removeFromTasks(_ value: Task)

    @objc(addTasks:)
    @NSManaged public func addToTasks(_ values: Set<Task>)

    @objc(removeTasks:)
    @NSManaged public func removeFromTasks(_ values: Set<Task>)
}

// MARK: - Generated accessors for sessions
extension Tag {

    @objc(addSessionsObject:)
    @NSManaged public func addToSessions(_ value: FocusSession)

    @objc(removeSessionsObject:)
    @NSManaged public func removeFromSessions(_ value: FocusSession)

    @objc(addSessions:)
    @NSManaged public func addToSessions(_ values: Set<FocusSession>)

    @objc(removeSessions:)
    @NSManaged public func removeFromSessions(_ values: Set<FocusSession>)
}

// MARK: - Generated accessors for timeRecords
extension Tag {

    @objc(addTimeRecordsObject:)
    @NSManaged public func addToTimeRecords(_ value: TimeRecord)

    @objc(removeTimeRecordsObject:)
    @NSManaged public func removeFromTimeRecords(_ value: TimeRecord)

    @objc(addTimeRecords:)
    @NSManaged public func addToTimeRecords(_ values: Set<TimeRecord>)

    @objc(removeTimeRecords:)
    @NSManaged public func removeFromTimeRecords(_ values: Set<TimeRecord>)
}

extension Tag: Identifiable {

}

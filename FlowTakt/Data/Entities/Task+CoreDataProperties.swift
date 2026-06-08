import Foundation
import CoreData

extension Task {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Task> {
        return NSFetchRequest<Task>(entityName: "Task")
    }

    @NSManaged public var id: UUID
    @NSManaged public var title: String
    @NSManaged public var notes: String?
    @NSManaged public var estimatedPomodoros: Int16
    @NSManaged public var completedPomodoros: Int16
    @NSManaged public var priority: Int16
    @NSManaged public var status: String
    @NSManaged public var dueDate: Date?
    @NSManaged public var completedAt: Date?
    @NSManaged public var displayOrder: Int16
    @NSManaged public var createdAt: Date
    @NSManaged public var updatedAt: Date

    @NSManaged public var estimatedDuration: Double
    @NSManaged public var startDate: Date?
    @NSManaged public var isRecurring: Bool
    @NSManaged public var recurrenceRule: String?
    @NSManaged public var recurrenceEndDate: Date?

    @NSManaged public var sessions: Set<FocusSession>
    @NSManaged public var tags: Set<Tag>

    @NSManaged public var parentTask: Task?
    @NSManaged public var subTasks: Set<Task>
    @NSManaged public var scheduleItems: Set<ScheduleItem>
    @NSManaged public var timeRecords: Set<TimeRecord>
}

// MARK: - Generated accessors for sessions
extension Task {

    @objc(addSessionsObject:)
    @NSManaged public func addToSessions(_ value: FocusSession)

    @objc(removeSessionsObject:)
    @NSManaged public func removeFromSessions(_ value: FocusSession)

    @objc(addSessions:)
    @NSManaged public func addToSessions(_ values: Set<FocusSession>)

    @objc(removeSessions:)
    @NSManaged public func removeFromSessions(_ values: Set<FocusSession>)
}

// MARK: - Generated accessors for tags
extension Task {

    @objc(addTagsObject:)
    @NSManaged public func addToTags(_ value: Tag)

    @objc(removeTagsObject:)
    @NSManaged public func removeFromTags(_ value: Tag)

    @objc(addTags:)
    @NSManaged public func addToTags(_ values: Set<Tag>)

    @objc(removeTags:)
    @NSManaged public func removeFromTags(_ values: Set<Tag>)
}

// MARK: - Generated accessors for subTasks
extension Task {

    @objc(addSubTasksObject:)
    @NSManaged public func addToSubTasks(_ value: Task)

    @objc(removeSubTasksObject:)
    @NSManaged public func removeFromSubTasks(_ value: Task)

    @objc(addSubTasks:)
    @NSManaged public func addToSubTasks(_ values: Set<Task>)

    @objc(removeSubTasks:)
    @NSManaged public func removeFromSubTasks(_ values: Set<Task>)
}

extension Task: Identifiable {

}

import Foundation
import CoreData

extension FocusSession {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<FocusSession> {
        return NSFetchRequest<FocusSession>(entityName: "FocusSession")
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

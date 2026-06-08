import Foundation
import CoreData

extension TimeRecord {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<TimeRecord> {
        return NSFetchRequest<TimeRecord>(entityName: "TimeRecord")
    }

    @NSManaged public var id: UUID
    @NSManaged public var startTime: Date
    @NSManaged public var endTime: Date?
    @NSManaged public var duration: Double
    @NSManaged public var note: String?
    @NSManaged public var project: String?
    @NSManaged public var isBillable: Bool
    @NSManaged public var createdAt: Date
    @NSManaged public var updatedAt: Date

    @NSManaged public var task: Task?
    @NSManaged public var tag: Tag?
}

extension TimeRecord: Identifiable {

}

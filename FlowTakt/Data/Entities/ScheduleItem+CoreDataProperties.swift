import Foundation
import CoreData

extension ScheduleItem {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<ScheduleItem> {
        return NSFetchRequest<ScheduleItem>(entityName: "ScheduleItem")
    }

    @NSManaged public var id: UUID
    @NSManaged public var title: String
    @NSManaged public var startDate: Date
    @NSManaged public var endDate: Date?
    @NSManaged public var isAllDay: Bool
    @NSManaged public var location: String?
    @NSManaged public var notes: String?
    @NSManaged public var colorHex: String?
    @NSManaged public var createdAt: Date
    @NSManaged public var updatedAt: Date

    @NSManaged public var task: Task?
}

extension ScheduleItem: Identifiable {

}

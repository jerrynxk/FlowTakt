import Foundation
import CoreData

extension HabitRecord {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<HabitRecord> {
        return NSFetchRequest<HabitRecord>(entityName: "HabitRecord")
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

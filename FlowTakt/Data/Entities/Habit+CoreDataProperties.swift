import Foundation
import CoreData

extension Habit {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Habit> {
        return NSFetchRequest<Habit>(entityName: "Habit")
    }

    @NSManaged public var id: UUID
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

}

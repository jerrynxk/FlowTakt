import Foundation
import CoreData

extension Achievement {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Achievement> {
        return NSFetchRequest<Achievement>(entityName: "Achievement")
    }

    @NSManaged public var id: UUID
    @NSManaged public var identifier: String
    @NSManaged public var title: String
    @NSManaged public var descriptionText: String?
    @NSManaged public var iconName: String?
    @NSManaged public var category: String
    @NSManaged public var thresholdValue: Int16
    @NSManaged public var isUnlocked: Bool
    @NSManaged public var unlockedAt: Date?
    @NSManaged public var createdAt: Date
}

extension Achievement: Identifiable {

}

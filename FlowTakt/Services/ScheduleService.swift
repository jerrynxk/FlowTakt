import Foundation
import CoreData

// MARK: - ScheduleService 协议

protocol ScheduleServiceProtocol {
    func createEvent(title: String, startDate: Date, endDate: Date?, isAllDay: Bool, location: String?, notes: String?, colorHex: String?, task: Task?) -> ScheduleItem
    func updateEvent(_ event: ScheduleItem, title: String?, startDate: Date?, endDate: Date?, isAllDay: Bool?, location: String?, notes: String?, colorHex: String?)
    func deleteEvent(_ event: ScheduleItem)
    func fetchEvents(from startDate: Date, to endDate: Date) -> [ScheduleItem]
    func fetchEventsForDate(_ date: Date) -> [ScheduleItem]
    func fetchAllEvents() -> [ScheduleItem]
}

// MARK: - 日程服务实现

final class ScheduleService: ScheduleServiceProtocol {
    private let persistenceController: PersistenceController

    private var viewContext: NSManagedObjectContext {
        persistenceController.viewContext
    }

    init(persistenceController: PersistenceController) {
        self.persistenceController = persistenceController
    }

    // MARK: - 创建

    func createEvent(title: String, startDate: Date, endDate: Date?, isAllDay: Bool, location: String?, notes: String?, colorHex: String?, task: Task?) -> ScheduleItem {
        let event = ScheduleItem(context: viewContext)
        event.id = UUID()
        event.title = title
        event.startDate = startDate
        event.endDate = endDate
        event.isAllDay = isAllDay
        event.location = location
        event.notes = notes
        event.colorHex = colorHex
        event.task = task
        event.createdAt = Date()
        event.updatedAt = Date()
        persistenceController.save()
        return event
    }

    // MARK: - 更新

    func updateEvent(_ event: ScheduleItem, title: String?, startDate: Date?, endDate: Date?, isAllDay: Bool?, location: String?, notes: String?, colorHex: String?) {
        if let title = title { event.title = title }
        if let startDate = startDate { event.startDate = startDate }
        if let endDate = endDate { event.endDate = endDate }
        if let isAllDay = isAllDay { event.isAllDay = isAllDay }
        if let location = location { event.location = location }
        if let notes = notes { event.notes = notes }
        if let colorHex = colorHex { event.colorHex = colorHex }
        event.updatedAt = Date()
        persistenceController.save()
    }

    // MARK: - 删除

    func deleteEvent(_ event: ScheduleItem) {
        viewContext.delete(event)
        persistenceController.save()
    }

    // MARK: - 查询

    func fetchEvents(from startDate: Date, to endDate: Date) -> [ScheduleItem] {
        let request = ScheduleItem.fetchRequest()
        // 时间范围交集：事件开始时间 < 查询结束时间 AND (事件结束时间为 nil OR 事件结束时间 > 查询开始时间)
        request.predicate = NSPredicate(
            format: "startDate < %@ AND (endDate == nil OR endDate > %@)",
            endDate as NSDate,
            startDate as NSDate
        )
        request.sortDescriptors = [NSSortDescriptor(keyPath: \ScheduleItem.startDate, ascending: true)]
        do {
            return try viewContext.fetch(request)
        } catch {
            print("获取日程列表失败：\(error.localizedDescription)")
            return []
        }
    }

    func fetchEventsForDate(_ date: Date) -> [ScheduleItem] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return []
        }
        return fetchEvents(from: startOfDay, to: endOfDay)
    }

    func fetchAllEvents() -> [ScheduleItem] {
        let request = ScheduleItem.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \ScheduleItem.startDate, ascending: true)]
        do {
            return try viewContext.fetch(request)
        } catch {
            print("获取全部日程失败：\(error.localizedDescription)")
            return []
        }
    }
}

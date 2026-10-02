import Foundation
import CoreData

// MARK: - ScheduleService 协议

protocol ScheduleServiceProtocol {
    func createEvent(title: String, startDate: Date, endDate: Date?, isAllDay: Bool, location: String?, notes: String?, colorHex: String?, category: ScheduleCategory, repeatRule: RepeatRule, reminderEnabled: Bool, reminderLeadMinutes: Int, task: Task?) -> ScheduleItem
    func updateEvent(_ event: ScheduleItem, title: String?, startDate: Date?, endDate: Date?, isAllDay: Bool?, location: String?, notes: String?, colorHex: String?, category: ScheduleCategory?, repeatRule: RepeatRule?, reminderEnabled: Bool?, reminderLeadMinutes: Int?)
    func deleteEvent(_ event: ScheduleItem)
    func fetchEvents(from startDate: Date, to endDate: Date) -> [ScheduleItem]
    func fetchEventsForDate(_ date: Date) -> [ScheduleItem]
    func fetchAllEvents() -> [ScheduleItem]
    /// 按 ID 跨月查询单个事件（Widget 深链定位用，不受当月加载范围限制）
    func fetchEvent(id: UUID) -> ScheduleItem?
}

// MARK: - 日程服务实现

@MainActor
final class ScheduleService: ScheduleServiceProtocol {
    private let persistenceController: PersistenceController

    private var viewContext: NSManagedObjectContext {
        persistenceController.viewContext
    }

    init(persistenceController: PersistenceController) {
        self.persistenceController = persistenceController
    }

    // MARK: - 创建

    func createEvent(title: String, startDate: Date, endDate: Date?, isAllDay: Bool, location: String?, notes: String?, colorHex: String?, category: ScheduleCategory, repeatRule: RepeatRule, reminderEnabled: Bool, reminderLeadMinutes: Int, task: Task?) -> ScheduleItem {
        let event = ScheduleItem(context: viewContext)
        event.id = UUID()
        event.title = title
        event.startDate = startDate
        event.endDate = endDate
        event.isAllDay = isAllDay
        event.location = location
        event.notes = notes
        event.colorHex = colorHex
        event.category = category.rawValue
        event.repeatRule = repeatRule.rawValue
        event.reminderEnabled = reminderEnabled
        event.reminderLeadMinutes = Int32(reminderLeadMinutes)
        event.task = task
        event.createdAt = Date()
        event.updatedAt = Date()
        persistenceController.save()
        return event
    }

    // MARK: - 更新

    func updateEvent(_ event: ScheduleItem, title: String?, startDate: Date?, endDate: Date?, isAllDay: Bool?, location: String?, notes: String?, colorHex: String?, category: ScheduleCategory?, repeatRule: RepeatRule?, reminderEnabled: Bool?, reminderLeadMinutes: Int?) {
        if let title = title { event.title = title }
        if let startDate = startDate { event.startDate = startDate }
        // 防御：结束时间不早于开始时间（含同时传入 startDate/endDate 的情形）
        if let endDate = endDate {
            let effectiveStart = startDate ?? event.startDate
            event.endDate = endDate < effectiveStart ? effectiveStart : endDate
        }
        if let isAllDay = isAllDay { event.isAllDay = isAllDay }
        if let location = location { event.location = location }
        if let notes = notes { event.notes = notes }
        if let colorHex = colorHex { event.colorHex = colorHex }
        if let category = category { event.category = category.rawValue }
        if let repeatRule = repeatRule { event.repeatRule = repeatRule.rawValue }
        if let reminderEnabled = reminderEnabled { event.reminderEnabled = reminderEnabled }
        if let reminderLeadMinutes = reminderLeadMinutes { event.reminderLeadMinutes = Int32(reminderLeadMinutes) }
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

    func fetchEvent(id: UUID) -> ScheduleItem? {
        let request = ScheduleItem.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        do {
            return try viewContext.fetch(request).first
        } catch {
            print("按 ID 获取日程失败：\(error.localizedDescription)")
            return nil
        }
    }
}

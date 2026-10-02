import Foundation
import CoreData
import UserNotifications
import WidgetKit

// MARK: - ReminderService 协议

protocol ReminderServiceProtocol {
    /// 全量重排所有提醒通知，并刷新小组件快照
    func rescheduleAll()
}

// MARK: - 提醒服务实现

/// 负责将「开启提醒」的日程项转换为本地通知，并向 App Group 写入小组件快照。
///
/// 调度策略：
/// - 生日 / 纪念日：`UNCalendarNotificationTrigger` 仅匹配 month/day(+提前量)，`repeats: true`
/// - 客户拜访 / 事件：匹配完整日期减提前量，`repeats: false`（一次性）
///
/// 通过稳定 identifier（`reminder_<uuid>`）保证重排幂等：同名再次 add 会覆盖旧的。
final class ReminderService: ReminderServiceProtocol {

    private let persistenceController: PersistenceController
    private let notificationCenter = UNUserNotificationCenter.current()
    /// rescheduleAll 去抖用的工作项，避免一次用户操作 / 一次 iCloud 远程合并触发多次全量重排
    private var rescheduleWorkItem: DispatchWorkItem?

    init(persistenceController: PersistenceController) {
        self.persistenceController = persistenceController

        // 监听显式变更（增删改后由 ViewModel 发出）
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRemindersChanged),
            name: .remindersDataChanged,
            object: nil
        )
        // 监听 CoreData 上下文变更（覆盖 iCloud 远程合并等隐式变更）
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleContextChange),
            name: .NSManagedObjectContextObjectsDidChange,
            object: persistenceController.viewContext
        )
        // 监听数据库重置：context.reset() 不触发 ObjectsDidChange，必须显式重排，
        // 否则已删除日程的 reminder_<uuid> 通知残留、Widget 快照保持旧数据
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDatabaseReset),
            name: .databaseDidReset,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - 触发入口

    @objc private func handleRemindersChanged() {
        rescheduleAll()
    }

    /// 数据库重置后：全量重排（内部清理所有已不存在的 reminder_* 请求并重写快照）
    @objc private func handleDatabaseReset(_ notification: Notification) {
        rescheduleAll()
    }

    @objc private func handleContextChange(_ notification: Notification) {
        // 仅当变更涉及 ScheduleItem 时才全量重排，避免任意实体保存都触发刷新
        guard let userInfo = notification.userInfo else {
            rescheduleAll()
            return
        }
        let keys = [NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey]
        let involvesScheduleItem = keys.contains { key in
            (userInfo[key] as? Set<NSManagedObject>)?.contains { $0.entity.name == "ScheduleItem" } ?? false
        }
        if involvesScheduleItem {
            rescheduleAll()
        }
    }

    /// 全量重排入口：做 300ms 去抖合并后再执行真正重排。
    ///
    /// 一次用户批量保存多个 `ScheduleItem`、或一次 iCloud 远程合并，都可能触发多次
    /// `NSManagedObjectContextObjectsDidChange`，去抖可避免重复全量重排 + 多次
    /// `WidgetCenter` 刷新 + 重复全表扫描连续天数。
    func rescheduleAll() {
        rescheduleWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.performReschedule()
        }
        rescheduleWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    /// 真正执行重排：在 viewContext 上读取已开启提醒的项，写快照、刷新 Widget、调度通知。
    ///
    /// 注意：所有对 `ScheduleItem` 托管对象属性的读取都在 `context.perform`（主队列）内完成，
    /// 仅将构建好的 `UNNotificationRequest`（值类型）交给后续异步 UN 调用，
    /// 避免在主上下文队列之外访问 Core Data 对象（iCloud 合并时存在竞态/崩溃风险）。
    private func performReschedule() {
        let context = persistenceController.viewContext
        context.perform { [weak self] in
            guard let self else { return }
            let items = self.fetchReminderItems(in: context)
            self.writeSnapshot(from: items)
            WidgetCenter.shared.reloadAllTimelines()

            // 在上下文队列内构建请求（此处已完成全部 item.* 读取）
            let builtRequests: [UNNotificationRequest] = items.compactMap { item in
                guard let trigger = self.fireDateComponents(for: item) else { return nil }
                let content = UNMutableNotificationContent()
                content.title = Self.notificationTitle(for: item)
                content.body = Self.notificationBody(for: item)
                content.sound = .default
                return UNNotificationRequest(
                    identifier: Self.identifier(for: item),
                    content: content,
                    trigger: UNCalendarNotificationTrigger(
                        dateMatching: trigger,
                        repeats: item.categoryEnum.repeatsYearly
                    )
                )
            }
            let currentIDs = Set(builtRequests.map { $0.identifier })
            self.scheduleNotifications(builtRequests, currentIDs: currentIDs)
            // 周报推送（内部判断授权与开关，幂等重排）
            self.scheduleWeeklyReport()
        }
    }

    // MARK: - 数据查询

    private func fetchReminderItems(in context: NSManagedObjectContext) -> [ScheduleItem] {
        let request = ScheduleItem.fetchRequest()
        request.predicate = NSPredicate(format: "reminderEnabled == YES")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \ScheduleItem.startDate, ascending: true)]
        return (try? context.fetch(request)) ?? []
    }

    // MARK: - 通知调度

    /// 仅在已授权时注册通知；未授权也不影响小组件快照。
    /// 入参为已在上下文队列构建好的请求，本方法及其回调不再触碰 Core Data 对象。
    private func scheduleNotifications(_ requests: [UNNotificationRequest], currentIDs: Set<String>) {
        notificationCenter.getNotificationSettings { [weak self] settings in
            guard settings.authorizationStatus == .authorized else { return }
            self?.applyNotifications(requests, currentIDs: currentIDs)
        }
    }

    private func applyNotifications(_ requests: [UNNotificationRequest], currentIDs: Set<String>) {
        notificationCenter.getPendingNotificationRequests { [weak self] pending in
            guard let self else { return }
            // 移除已不存在（被删除/关闭提醒）的 reminder_* 请求
            let toRemove = pending
                .map(\.identifier)
                .filter { $0.hasPrefix("reminder_") && !currentIDs.contains($0) }
            if !toRemove.isEmpty {
                notificationCenter.removePendingNotificationRequests(withIdentifiers: toRemove)
            }
            for request in requests {
                notificationCenter.add(request)
            }
        }
    }

    /// 计算通知触发的时间分量：
    /// - 年重复：仅 month/day + 原时间 - 提前量
    /// - 一次性：完整日期 - 提前量；若提前量窗口已过但事件尚未开始，退化为「事件开始时提醒」，
    ///   避免当天提醒静默丢失；仅当整个事件都已过去才跳过
    private func fireDateComponents(for item: ScheduleItem) -> DateComponents? {
        let cal = Calendar.current
        guard let occ = item.nextOccurrenceDate else { return nil }
        let fire = cal.date(byAdding: .minute, value: -item.reminderLeadMinutesInt, to: occ) ?? occ

        if item.categoryEnum.repeatsYearly {
            return cal.dateComponents([.month, .day, .hour, .minute], from: fire)
        }
        // 一次性：触发时间已过但事件尚未开始 → 退化为准点提醒（提前量窗口已错过）
        if fire < Date() {
            guard occ >= Date() else { return nil }
            return cal.dateComponents([.year, .month, .day, .hour, .minute], from: occ)
        }
        return cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
    }

    private static func identifier(for item: ScheduleItem) -> String {
        "reminder_\(item.id.uuidString)"
    }

    private static func notificationTitle(for item: ScheduleItem) -> String {
        let lead = item.reminderLeadMinutesInt
        if lead > 0 {
            return "\(item.categoryEnum.displayName)提醒 · 提前\(leadText(lead))"
        }
        return "\(item.categoryEnum.displayName)提醒"
    }

    private static func notificationBody(for item: ScheduleItem) -> String {
        item.title
    }

    static func leadText(_ minutes: Int) -> String {
        if minutes % 1440 == 0 { return "\(minutes / 1440)天" }
        if minutes >= 60 && minutes % 60 == 0 { return "\(minutes / 60)小时" }
        return "\(minutes)分钟"
    }

    // MARK: - 小组件快照

    private func writeSnapshot(from items: [ScheduleItem]) {
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: Date())

        let reminders: [WidgetReminder] = items.compactMap { item in
            guard let occ = item.nextOccurrenceDate, occ >= startOfToday else { return nil }
            return WidgetReminder(
                id: item.id.uuidString,
                title: item.title,
                categoryRaw: item.categoryEnum.rawValue,
                colorHex: item.colorHex,
                nextDate: occ,
                isAllDay: item.isAllDay
            )
        }
        .sorted { $0.nextDate < $1.nextDate }
        .prefix(10)
        .map { $0 }

        WidgetDataStore.write(WidgetSnapshot(reminders: reminders, updatedAt: Date()))
    }

    // MARK: - 每周日专注周报推送

    /// 每周日晚（周日 20:00）推送本周专注汇总。
    /// 先取消已有请求保证幂等；仅当用户开启（UserDefaults weeklyReportEnabled）且已授权时注册。
    func scheduleWeeklyReport() {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [Self.weeklyReportIdentifier])
        guard UserDefaults.standard.bool(forKey: "weeklyReportEnabled") else { return }
        notificationCenter.getNotificationSettings { [weak self] settings in
            guard settings.authorizationStatus == .authorized else { return }
            self?.registerWeeklyReportNotification()
        }
    }

    private func registerWeeklyReportNotification() {
        let context = persistenceController.viewContext
        context.perform { [weak self] in
            guard let self else { return }
            let content = UNMutableNotificationContent()
            content.title = L10n.shared.本周专注周报
            // 修复（审查 #8）：repeating trigger 复用注册时的 content，
            // 动态汇总会在推送时过期；改为固定文案引导打开 App 查看实时统计
            content.body = L10n.shared.本周专注周报内容
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: DateComponents(hour: 20, minute: 0, weekday: 1),
                repeats: true
            )
            let request = UNNotificationRequest(
                identifier: Self.weeklyReportIdentifier,
                content: content,
                trigger: trigger
            )
            self.notificationCenter.add(request)
        }
    }

    private static let weeklyReportIdentifier = "flowtakt_weekly_report"
}

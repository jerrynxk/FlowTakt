import Foundation
import Combine
import CoreData

// MARK: - ScheduleViewModel

final class ScheduleViewModel: ObservableObject {
    // MARK: - Dependencies

    private let scheduleService: ScheduleServiceProtocol
    private let persistenceController: PersistenceController

    // MARK: - Published Properties

    /// 当前加载的日程事件列表
    @Published var events: [ScheduleItem] = []
    /// 当前选中的日期
    @Published var selectedDate: Date = Date()
    /// 当前浏览的月份
    @Published var currentMonth: Date = Date()

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init(scheduleService: ScheduleServiceProtocol, persistenceController: PersistenceController) {
        self.scheduleService = scheduleService
        self.persistenceController = persistenceController

        // 初始化时加载当月事件
        refreshForMonth(currentMonth)

        // 监听 CoreData 上下文变化，自动刷新
        NotificationCenter.default.publisher(
            for: .NSManagedObjectContextObjectsDidChange,
            object: persistenceController.viewContext
        )
        .receive(on: DispatchQueue.main)
        .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
        .sink { [weak self] _ in
            guard let self = self else { return }
            self.refreshForMonth(self.currentMonth)
        }
        .store(in: &cancellables)

        // 监听数据库重置通知，立即清空旧 ManagedObject 引用防止崩溃
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDatabaseWillReset),
            name: .databaseWillReset,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDatabaseDidReset),
            name: .databaseDidReset,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Private

    @objc private func handleDatabaseWillReset() {
        events = []
    }

    @objc private func handleDatabaseDidReset() {
        DispatchQueue.main.async { [weak self] in
            self?.refreshForMonth(self?.currentMonth ?? Date())
        }
    }

    // MARK: - Public Methods

    /// 刷新当月全部事件
    func refreshEvents() {
        events = scheduleService.fetchAllEvents()
    }

    /// 刷新指定日期的事件
    /// - Parameter date: 目标日期
    func refreshForDate(_ date: Date) {
        events = scheduleService.fetchEventsForDate(date)
        selectedDate = date
    }

    /// 刷新指定月份的事件
    /// - Parameter date: 月份中的任意一天
    func refreshForMonth(_ date: Date) {
        let calendar = Calendar.current
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: date)),
              let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) else {
            return
        }
        events = scheduleService.fetchEvents(from: monthStart, to: monthEnd)
        currentMonth = date
    }

    /// 按 ID 跨月查找事件（Widget 深链定位：目标事件可能不在当前加载的当月范围内）
    func findEvent(byID id: UUID) -> ScheduleItem? {
        scheduleService.fetchEvent(id: id)
    }

    /// 周视图事件（按 selectedDate 所在周加载，跨月时与月视图数据相互独立）
    @Published var weekEvents: [ScheduleItem] = []
    /// 当前周视图的起始日（按系统首日星期）
    @Published var currentWeekStart: Date = Date()

    /// 加载指定日期所在周的事件（半开区间 [周首日, 下周一)）
    func refreshForWeek(containing date: Date) {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: date)
        let weekday = cal.component(.weekday, from: dayStart)
        let firstWeekday = cal.firstWeekday
        let diff = (weekday - firstWeekday + 7) % 7
        guard let weekStart = cal.date(byAdding: .day, value: -diff, to: dayStart),
              let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStart) else { return }
        weekEvents = scheduleService.fetchEvents(from: weekStart, to: weekEnd)
        currentWeekStart = weekStart
    }

    /// 周视图前后翻周
    func shiftWeek(by weeks: Int) {
        guard let newStart = Calendar.current.date(byAdding: .day, value: weeks * 7, to: currentWeekStart) else { return }
        refreshForWeek(containing: newStart)
    }

    /// 创建新日程事件
    /// - Parameters:
    ///   - title: 事件标题
    ///   - startDate: 开始时间
    ///   - endDate: 结束时间（可选）
    ///   - isAllDay: 是否全天事件
    ///   - location: 地点（可选）
    ///   - notes: 备注（可选）
    ///   - colorHex: 颜色十六进制值（可选）
    ///   - category: 分类（事件/生日/纪念日/客户拜访）
    ///   - repeatRule: 重复规则
    ///   - reminderEnabled: 是否开启提醒
    ///   - reminderLeadMinutes: 提前提醒分钟数
    ///   - task: 关联任务（可选）
    func createEvent(title: String, startDate: Date, endDate: Date?, isAllDay: Bool, location: String?, notes: String?, colorHex: String?, category: ScheduleCategory, repeatRule: RepeatRule, reminderEnabled: Bool, reminderLeadMinutes: Int, task: Task?) {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        _ = scheduleService.createEvent(
            title: title,
            startDate: startDate,
            endDate: endDate,
            isAllDay: isAllDay,
            location: location,
            notes: notes,
            colorHex: colorHex,
            category: category,
            repeatRule: repeatRule,
            reminderEnabled: reminderEnabled,
            reminderLeadMinutes: reminderLeadMinutes,
            task: task
        )

        refreshForMonth(currentMonth)
        notifyRemindersChanged()
    }

    /// 更新现有日程事件
    /// - Parameters:
    ///   - event: 要更新的事件
    ///   - title: 新标题（可选）
    ///   - startDate: 新开始时间（可选）
    ///   - endDate: 新结束时间（可选）
    ///   - isAllDay: 是否全天事件（可选）
    ///   - location: 新地点（可选）
    ///   - notes: 新备注（可选）
    ///   - colorHex: 新颜色（可选）
    ///   - category: 新分类（可选）
    ///   - repeatRule: 新重复规则（可选）
    ///   - reminderEnabled: 是否开启提醒（可选）
    ///   - reminderLeadMinutes: 提前提醒分钟数（可选）
    func updateEvent(_ event: ScheduleItem, title: String?, startDate: Date?, endDate: Date?, isAllDay: Bool?, location: String?, notes: String?, colorHex: String?, category: ScheduleCategory?, repeatRule: RepeatRule?, reminderEnabled: Bool?, reminderLeadMinutes: Int?) {
        scheduleService.updateEvent(
            event,
            title: title,
            startDate: startDate,
            endDate: endDate,
            isAllDay: isAllDay,
            location: location,
            notes: notes,
            colorHex: colorHex,
            category: category,
            repeatRule: repeatRule,
            reminderEnabled: reminderEnabled,
            reminderLeadMinutes: reminderLeadMinutes
        )

        refreshForMonth(currentMonth)
        notifyRemindersChanged()
    }

    /// 删除日程事件
    /// - Parameter event: 要删除的事件
    func deleteEvent(_ event: ScheduleItem) {
        scheduleService.deleteEvent(event)
        refreshForMonth(currentMonth)
        notifyRemindersChanged()
    }

    /// 提醒数据已变更，通知 ReminderService 重排通知并刷新小组件
    private func notifyRemindersChanged() {
        NotificationCenter.default.post(name: .remindersDataChanged, object: nil)
    }
}

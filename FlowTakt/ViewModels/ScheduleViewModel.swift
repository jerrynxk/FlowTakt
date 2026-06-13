import Foundation
import Combine
import CoreData

// MARK: - ScheduleViewModel

final class ScheduleViewModel: ObservableObject {
    // MARK: - Dependencies

    private let scheduleService: ScheduleServiceProtocol

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

    init(scheduleService: ScheduleServiceProtocol) {
        self.scheduleService = scheduleService

        // 初始化时加载当月事件
        refreshForMonth(currentMonth)

        // 监听 CoreData 上下文变化，自动刷新
        NotificationCenter.default.publisher(
            for: .NSManagedObjectContextObjectsDidChange,
            object: nil
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            guard let self = self else { return }
            self.refreshForMonth(self.currentMonth)
        }
        .store(in: &cancellables)
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

    /// 创建新日程事件
    /// - Parameters:
    ///   - title: 事件标题
    ///   - startDate: 开始时间
    ///   - endDate: 结束时间（可选）
    ///   - isAllDay: 是否全天事件
    ///   - location: 地点（可选）
    ///   - notes: 备注（可选）
    ///   - colorHex: 颜色十六进制值（可选）
    ///   - task: 关联任务（可选）
    func createEvent(title: String, startDate: Date, endDate: Date?, isAllDay: Bool, location: String?, notes: String?, colorHex: String?, task: Task?) {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        _ = scheduleService.createEvent(
            title: title,
            startDate: startDate,
            endDate: endDate,
            isAllDay: isAllDay,
            location: location,
            notes: notes,
            colorHex: colorHex,
            task: task
        )

        refreshForMonth(currentMonth)
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
    func updateEvent(_ event: ScheduleItem, title: String?, startDate: Date?, endDate: Date?, isAllDay: Bool?, location: String?, notes: String?, colorHex: String?) {
        scheduleService.updateEvent(
            event,
            title: title,
            startDate: startDate,
            endDate: endDate,
            isAllDay: isAllDay,
            location: location,
            notes: notes,
            colorHex: colorHex
        )

        refreshForMonth(currentMonth)
    }

    /// 删除日程事件
    /// - Parameter event: 要删除的事件
    func deleteEvent(_ event: ScheduleItem) {
        scheduleService.deleteEvent(event)
        refreshForMonth(currentMonth)
    }
}

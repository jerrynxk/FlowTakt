import Foundation
import Combine
import CoreData

// MARK: - 每日统计数据

struct DailyStats: Identifiable {
    let date: Date
    let completedPomodoros: Int
    let totalDuration: TimeInterval

    var id: Date { date }
}

// MARK: - StatsViewModel

final class StatsViewModel: ObservableObject {
    // MARK: - Dependencies

    private let focusService: FocusServiceProtocol
    private let taskService: TaskServiceProtocol
    private let persistenceController: PersistenceController

    private var viewContext: NSManagedObjectContext {
        persistenceController.viewContext
    }

    // MARK: - Published Properties

    /// 今日所有专注会话
    @Published var todaySessions: [FocusSession] = []
    /// 本周每日统计数据（最近 7 天）
    @Published var weeklyData: [DailyStats] = []
    /// 本月每日统计数据
    @Published var monthlyData: [DailyStats] = []
    /// 累计完成的番茄钟总数
    @Published var totalCompletedPomodoros: Int = 0
    /// 当前连续天数
    @Published var currentStreak: Int = 0
    /// 今日专注总时长（秒）
    @Published var todayDuration: TimeInterval = 0
    /// 完成率（今日已完成会话 / 今日总会话）
    @Published var completionRate: Double = 0

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init(focusService: FocusServiceProtocol, taskService: TaskServiceProtocol, persistenceController: PersistenceController) {
        self.focusService = focusService
        self.taskService = taskService
        self.persistenceController = persistenceController

        // 初始化时加载数据
        refresh()

        // 监听 CoreData 上下文变化，自动刷新
        NotificationCenter.default.publisher(
            for: .NSManagedObjectContextObjectsDidChange,
            object: viewContext
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.refresh()
        }
        .store(in: &cancellables)
    }

    // MARK: - Public Methods

    /// 刷新所有统计数据
    func refresh() {
        todaySessions = focusService.fetchTodaysSessions()
        fetchWeeklyData()
        fetchMonthlyData()
        computeTotals()
    }

    /// 获取本周每日数据（近 7 天）
    func fetchWeeklyData() {
        let calendar = Calendar.current
        let today = Date()
        var dailyStats: [DailyStats] = []

        // 获取最近 7 天所有已完成的会话
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -6, to: today.startOfDay)!
        let sessions = fetchCompletedSessions(from: sevenDaysAgo, to: today.endOfDay)

        for dayOffset in (0..<7).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today.startOfDay) else {
                continue
            }
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: date)!.addingTimeInterval(-1)
            let daySessions = sessions.filter { session in
                session.startTime >= date && session.startTime <= dayEnd
            }
            let completedCount = daySessions.filter { $0.isCompleted }.count
            let totalDuration = daySessions.reduce(0) { $0 + $1.actualDuration }

            dailyStats.append(DailyStats(
                date: date,
                completedPomodoros: completedCount,
                totalDuration: totalDuration
            ))
        }

        weeklyData = dailyStats
    }

    /// 获取本月每日数据
    func fetchMonthlyData() {
        let calendar = Calendar.current
        let today = Date()
        let monthStart = today.startOfMonth
        guard let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart)?.addingTimeInterval(-1) else {
            return
        }

        let components = calendar.dateComponents([.year, .month], from: today)
        guard let range = calendar.range(of: .day, in: .month, for: today) else { return }

        let sessions = fetchCompletedSessions(from: monthStart, to: monthEnd)
        var dailyStats: [DailyStats] = []

        for day in 1...range.count {
            guard let date = calendar.date(from: DateComponents(
                year: components.year,
                month: components.month,
                day: day
            )) else { continue }

            let dayEnd = calendar.date(byAdding: .day, value: 1, to: date)!.addingTimeInterval(-1)
            let daySessions = sessions.filter { session in
                session.startTime >= date && session.startTime <= dayEnd
            }
            let completedCount = daySessions.filter { $0.isCompleted }.count
            let totalDuration = daySessions.reduce(0) { $0 + $1.actualDuration }

            dailyStats.append(DailyStats(
                date: date,
                completedPomodoros: completedCount,
                totalDuration: totalDuration
            ))
        }

        monthlyData = dailyStats
    }

    // MARK: - Private Methods

    private func computeTotals() {
        // 计算今日总时长
        todayDuration = todaySessions.reduce(0) { $0 + $1.actualDuration }

        // 计算今日完成率
        let totalCount = todaySessions.count
        let completedCount = todaySessions.filter { $0.isCompleted }.count
        completionRate = totalCount > 0 ? Double(completedCount) / Double(totalCount) : 0

        // 计算累计完成的番茄钟数
        totalCompletedPomodoros = fetchAllCompletedSessions().count

        // 计算当前连续天数
        currentStreak = computeStreak()
    }

    /// 获取指定日期范围内的所有会话
    private func fetchCompletedSessions(from startDate: Date, to endDate: Date) -> [FocusSession] {
        let request = FocusSession.fetchRequest()
        request.predicate = NSPredicate(
            format: "startTime >= %@ AND startTime <= %@",
            startDate as NSDate,
            endDate as NSDate
        )
        request.sortDescriptors = [NSSortDescriptor(keyPath: \FocusSession.startTime, ascending: true)]
        do {
            return try viewContext.fetch(request)
        } catch {
            print("获取会话数据失败：\(error.localizedDescription)")
            return []
        }
    }

    /// 获取所有已完成的会话
    private func fetchAllCompletedSessions() -> [FocusSession] {
        let request = FocusSession.fetchRequest()
        request.predicate = NSPredicate(format: "status == %@", SessionStatus.completed.rawValue)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \FocusSession.startTime, ascending: false)]
        do {
            return try viewContext.fetch(request)
        } catch {
            print("获取已完成会话失败：\(error.localizedDescription)")
            return []
        }
    }

    /// 计算连续天数（从今天开始往前数连续有完成会话的天数）
    private func computeStreak() -> Int {
        let sessions = fetchAllCompletedSessions()
        guard !sessions.isEmpty else { return 0 }

        let calendar = Calendar.current
        var streak = 0
        var currentDate = Date().startOfDay

        while true {
            let sessionsOnDate = sessions.filter {
                calendar.isDate($0.startTime, inSameDayAs: currentDate)
            }
            if sessionsOnDate.isEmpty {
                break
            }
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: currentDate) else {
                break
            }
            currentDate = previousDay
        }

        return streak
    }
}

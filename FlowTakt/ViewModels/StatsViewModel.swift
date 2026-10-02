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
    // 保留注入的 persistenceController 以兼容既有构造签名（统计查询一律走 focusService）
    private let persistenceController: PersistenceController

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
    /// 年热力图：过去一年内「日期 → 当日完成番茄数」（A5）
    @Published var yearlyCounts: [Date: Int] = [:]
    /// 年热力图：过去一年内有完成记录的天数
    @Published var yearlyTotalDays: Int = 0

    // MARK: - 中断洞察（计算属性，由 todaySessions 派生）

    /// 今日中断（放弃）的会话数
    var todayInterruptedCount: Int {
        todaySessions.filter { $0.status == SessionStatus.abandoned.rawValue }.count
    }

    /// 今日最近一次中断原因（无则 nil）
    var lastInterruptionReason: String? {
        todaySessions
            .filter { $0.status == SessionStatus.abandoned.rawValue }
            .sorted { $0.updatedAt > $1.updatedAt }
            .first?.interruptionReason
    }

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
            object: persistenceController.viewContext
        )
        .receive(on: DispatchQueue.main)
        .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.refresh()
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

    // MARK: - Private Methods

    @objc private func handleDatabaseWillReset() {
        // 立即清空已删除的 ManagedObject 引用
        todaySessions = []
        weeklyData = []
        monthlyData = []
        totalCompletedPomodoros = 0
        currentStreak = 0
        todayDuration = 0
        completionRate = 0
    }

    @objc private func handleDatabaseDidReset() {
        // 异步重新加载
        DispatchQueue.main.async { [weak self] in
            self?.refresh()
        }
    }

    // MARK: - Public Methods

    /// 刷新所有统计数据
    func refresh() {
        todaySessions = focusService.fetchTodaysSessions()
        fetchWeeklyData()
        fetchMonthlyData()
        // 单次全量拉取已完成会话，computeTotals / computeStreak 共用，避免重复全表扫描
        let allCompleted = fetchAllCompletedSessions()
        computeTotals(allCompleted: allCompleted)
    }

    /// 获取本周每日数据（近 7 天）
    func fetchWeeklyData() {
        let calendar = Calendar.current
        let today = Date()
        var dailyStats: [DailyStats] = []

        // 获取最近 7 天所有已完成的会话（审查 #13：guard 替代强制解包）
        guard let sevenDaysAgo = calendar.date(byAdding: .day, value: -6, to: today.startOfDay) else { return }
        let sessions = fetchCompletedSessions(from: sevenDaysAgo, to: today.endOfDay)
        // 按天分组，将 O(天数 × 会话) 降为 O(会话)
        let grouped = Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.startTime) }

        for dayOffset in (0..<7).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today.startOfDay) else {
                continue
            }
            let daySessions = grouped[date] ?? []
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
        // 按天分组，将 O(天数 × 会话) 降为 O(会话)
        let grouped = Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.startTime) }
        var dailyStats: [DailyStats] = []

        // 崩溃修复（2026-10-02）：`ClosedRange` 要求 lower <= upper，
        // 若 range.count 为 0 则 `1...0` 触发 Fatal error（区间构造 trap）。
        // max(1, ...) 兜底，公历 range 恒为 28...31，此处为纯防御。
        for day in 1...max(1, range.count) {
            guard let date = calendar.date(from: DateComponents(
                year: components.year,
                month: components.month,
                day: day
            )) else { continue }

            let daySessions = grouped[date] ?? []
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

    private func computeTotals(allCompleted: [FocusSession]) {
        // 计算今日总时长（仅统计已完成会话，interrupted/abandoned 不计入）
        todayDuration = todaySessions.filter { $0.isCompleted }.reduce(0) { $0 + $1.actualDuration }

        // 计算今日完成率
        let totalCount = todaySessions.count
        let completedCount = todaySessions.filter { $0.isCompleted }.count
        completionRate = totalCount > 0 ? Double(completedCount) / Double(totalCount) : 0

        // 计算累计完成的番茄钟数（复用 refresh() 已拉取的全量结果，避免重复全表扫描）
        totalCompletedPomodoros = allCompleted.count

        // 计算当前连续天数（复用同一次全量结果）
        currentStreak = computeStreak(allCompleted: allCompleted)

        // 派生年热力图（复用同一次全量结果，避免重复扫描）
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: todayStart) ?? todayStart
        var yearMap: [Date: Int] = [:]
        for session in allCompleted {
            let day = calendar.startOfDay(for: session.startTime)
            if day >= oneYearAgo {
                yearMap[day, default: 0] += 1
            }
        }
        yearlyCounts = yearMap
        yearlyTotalDays = yearMap.count

        // 写入今日专注摘要到 App Group，供锁屏 Widget「今日专注」读取
        let todayCompleted = todaySessions.filter { $0.isCompleted }.count
        let todayMinutes = Int(todayDuration / 60)
        WidgetDataStore.writeFocusSummary(WidgetDataStore.FocusSummary(
            completedPomodoros: todayCompleted,
            totalMinutes: todayMinutes,
            updatedAt: Date()
        ))
    }

    /// 获取指定日期范围内的已完成会话（经 FocusService，遵循 VM → Service 架构约定）
    private func fetchCompletedSessions(from startDate: Date, to endDate: Date) -> [FocusSession] {
        focusService.fetchCompletedSessions(from: startDate, to: endDate)
    }

    /// 获取所有已完成的会话（经 FocusService）
    private func fetchAllCompletedSessions() -> [FocusSession] {
        focusService.fetchAllCompletedSessions()
    }

    /// 计算连续天数（从今天开始往前数连续有完成会话的天数）
    /// Optimized: O(n+m) instead of O(n×m) by using a Set of completed dates
    private func computeStreak(allCompleted: [FocusSession]) -> Int {
        guard !allCompleted.isEmpty else { return 0 }

        let calendar = Calendar.current
        let completedDates = Set(allCompleted.map { calendar.startOfDay(for: $0.startTime) })

        var streak = 0
        var currentDate = Date().startOfDay

        while streak < 10000 {
            if completedDates.contains(currentDate) {
                streak += 1
                guard let previousDay = calendar.date(byAdding: .day, value: -1, to: currentDate) else {
                    break
                }
                currentDate = previousDay
            } else {
                break
            }
        }

        return streak
    }
}

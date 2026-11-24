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

// MARK: - 标签耗时分布（用户反馈 2026-11-19）

/// 单个标签在某时间范围内的专注耗时。
/// 判据：番茄钟（completed + earlyCompleted）与正计时记录都计入，按标签单归属聚合，
/// 因此 `所有条目 duration 之和 == 该范围总专注时长` 恒成立，用户可自行核对。
struct TagDuration: Identifiable, Equatable {
    let id: UUID
    let name: String
    let colorHex: String?
    let duration: TimeInterval
    /// 占该范围总时长的比例（0...1）
    let ratio: Double
}

// MARK: - StatsViewModel

final class StatsViewModel: ObservableObject {
    // MARK: - Dependencies

    private let focusService: FocusServiceProtocol
    private let taskService: TaskServiceProtocol
    /// 正计时服务（用户反馈 2026-11-17）：其时长计入「专注总和」。
    /// 可选注入以兼容 Preview 旧构造签名；生产路径由 AppDependency 注入真实实例。
    private let timeRecordService: TimeRecordServiceProtocol?
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

    // MARK: - 专注时长汇总（用户反馈 2026-11-19）
    //
    // 背景：番茄时长可自定义，"完成了几个番茄"参考价值有限。用户需要看到**总专注时长**，
    // 以及按标签分类的时间分配。口径与今日总和一致 ——
    // 番茄钟（completed + earlyCompleted）+ 正计时记录，均按净时长计入。

    /// 近 7 天专注总时长（秒）
    @Published var weekDuration: TimeInterval = 0
    /// 本月专注总时长（秒）
    @Published var monthDuration: TimeInterval = 0
    /// 累计专注总时长（秒）
    @Published var totalDuration: TimeInterval = 0
    /// 近 7 天按标签耗时（降序）
    @Published var weekTagDurations: [TagDuration] = []
    /// 本月按标签耗时（降序）
    @Published var monthTagDurations: [TagDuration] = []
    /// 今年按标签耗时（降序，2026-11-22 用户反馈）
    @Published var yearTagDurations: [TagDuration] = []
    /// 累计（全部历史）按标签耗时（降序，2026-11-22 用户反馈）
    @Published var allTagDurations: [TagDuration] = []
    /// 自定义区间按标签耗时（降序，2026-11-22 用户反馈）
    @Published var customTagDurations: [TagDuration] = []

    // MARK: - 中断洞察（计算属性，由 todaySessions 派生）

    /// 今日中断（放弃 / 提前结束）的会话数。
    /// 用户反馈 2026-11-17：提前结束改为 earlyCompleted 后，仍属"未完成计划的中断"，
    /// 且用户可能填了中断原因，须继续纳入洞察，否则原因会丢失。
    var todayInterruptedCount: Int {
        todaySessions.filter { $0.isInterruption }.count
    }

    /// 今日最近一次中断原因（无则 nil）
    var lastInterruptionReason: String? {
        todaySessions
            // 只取「带原因」的中断：最近一次提前结束若未填原因（单击停止的默认路径），
            // 不得覆盖此前用户明确填写的原因（审查修复 2026-11-17）。
            .filter { $0.isInterruption && $0.interruptionReason != nil }
            .sorted { $0.updatedAt > $1.updatedAt }
            .first?.interruptionReason
    }

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()

    /// 最近一次 refresh() 的时长口径快照，供「自定义」区间即时重算，
    /// 避免切换日期时重复全表扫描（2026-11-22 用户反馈）
    private var cachedDurationSessions: [FocusSession] = []
    private var cachedDurationRecords: [TimeRecord] = []
    private var customRange: (start: Date, end: Date)?

    // MARK: - Init

    init(focusService: FocusServiceProtocol,
         taskService: TaskServiceProtocol,
         persistenceController: PersistenceController,
         timeRecordService: TimeRecordServiceProtocol? = nil) {
        self.focusService = focusService
        self.taskService = taskService
        self.persistenceController = persistenceController
        self.timeRecordService = timeRecordService

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
        weekDuration = 0
        monthDuration = 0
        totalDuration = 0
        weekTagDurations = []
        monthTagDurations = []
        yearTagDurations = []
        allTagDurations = []
        customTagDurations = []
        cachedDurationSessions = []
        cachedDurationRecords = []
        customRange = nil
        yearlyCounts = [:]
        yearlyTotalDays = 0
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
        // 修复（2026-10-14 审查 P1-1）：今日统计口径统一为「专注阶段」——
// 专注页迷你统计、统计页今日概览/完成率、锁屏「今日专注」摘要、Siri 今日摘要全部读这一份数组，
// 避免休息阶段被计入（此前同一 App 里「今日积分」在统计页是 20、成就页是 10）。
        todaySessions = focusService.fetchTodayFocusSessions()
        // 修复（2026-10-14 P2）：单次全量拉取已完成会话（已按 phase == focus 过滤），
        // computeTotals / computeStreak / 周视图 / 月视图共用同一份数据 → 查询次数 4 → 2。
        // 用户反馈 2026-11-17：时长统计另拉一份含 earlyCompleted 的集合，
        // 与「番茄数/连续天数/热力图」口径分离，避免提前结束被算作完成番茄。
        let allCompleted = fetchAllCompletedSessions()
        let allForDuration = focusService.fetchAllSessionsForDuration()
        computeTotals(allCompleted: allCompleted)
        fetchWeeklyData(from: allCompleted, durationSource: allForDuration)
        fetchMonthlyData(from: allCompleted, durationSource: allForDuration)
        // 正计时记录：**一次**全量拉取，周/月叠加与标签分布共用同一份快照
        // （2026-11-19 审查：原实现两次查询——区间一次 + 全量一次，且两处若口径漂移
        //  会出现「周趋势里有、本周时长里没有」的矛盾）。
        let timeRecords = timeRecordService?.fetchAllRecords() ?? []
        // 用户反馈 2026-11-17：正计时（TimeRecord）时长并入周/月总和。
        applyTimeRecordDurationsToWeeklyAndMonthly(records: timeRecords)
        // 用户反馈 2026-11-19：总时长汇总 + 按标签耗时分布（含正计时）
        computeDurationSummary(allForDuration: allForDuration, timeRecords: timeRecords)
    }

    /// 获取本周每日数据（近 7 天）
    /// - Parameters:
    ///   - source: 已完成会话（番茄数口径，仅 completed），nil 时自行查询
    ///   - durationSource: 计入时长的会话（completed + earlyCompleted），nil 时自行查询
    func fetchWeeklyData(from source: [FocusSession]? = nil, durationSource: [FocusSession]? = nil) {
        let calendar = Calendar.current
        let today = Date()
        var dailyStats: [DailyStats] = []

        // 获取最近 7 天所有已完成的会话（审查 #13：guard 替代强制解包）
        guard let sevenDaysAgo = calendar.date(byAdding: .day, value: -6, to: today.startOfDay) else { return }
        // 性能约束（2026-10-15 审查 P2-V7）：`source` 兜底路径（nil 时自行查询）仅为
        // 兼容旧调用点保留；主路径 `refresh()` 必须传入一次性拉取的 allCompleted，
        // 避免与 fetchMonthlyData/computeTotals 各查一遍（4 次全表扫描）。
        // 新代码禁止以 nil 调用本方法。
        let sessions = source ?? fetchCompletedSessions(from: sevenDaysAgo, to: today.endOfDay)
        let durationSessions = durationSource ?? focusService.fetchSessionsForDuration(from: sevenDaysAgo, to: today.endOfDay)
        // 按天分组，将 O(天数 × 会话) 降为 O(会话)
        let grouped = Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.startTime) }
        let durationGrouped = Dictionary(grouping: durationSessions) { calendar.startOfDay(for: $0.startTime) }

        for dayOffset in (0..<7).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today.startOfDay) else {
                continue
            }
            let daySessions = grouped[date] ?? []
            let dayDurationSessions = durationGrouped[date] ?? []
            let completedCount = daySessions.filter { $0.isCompleted }.count
            // 时长口径：completed + earlyCompleted（提前结束的净专注时长也算进去）
            let totalDuration = dayDurationSessions.filter { $0.countsTowardDuration }.reduce(0) { $0 + $1.actualDuration }

            dailyStats.append(DailyStats(
                date: date,
                completedPomodoros: completedCount,
                totalDuration: totalDuration
            ))
        }

        weeklyData = dailyStats
    }

    /// 获取本月每日数据
    /// - Parameters:
    ///   - source: 已完成会话（番茄数口径，仅 completed），nil 时自行查询
    ///   - durationSource: 计入时长的会话（completed + earlyCompleted），nil 时自行查询
    func fetchMonthlyData(from source: [FocusSession]? = nil, durationSource: [FocusSession]? = nil) {
        let calendar = Calendar.current
        let today = Date()
        let monthStart = today.startOfMonth
        guard let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart)?.addingTimeInterval(-1) else {
            return
        }

        let components = calendar.dateComponents([.year, .month], from: today)
        guard let range = calendar.range(of: .day, in: .month, for: today) else { return }

        let sessions = source ?? fetchCompletedSessions(from: monthStart, to: monthEnd)
        let durationSessions = durationSource ?? focusService.fetchSessionsForDuration(from: monthStart, to: monthEnd)
        // 按天分组，将 O(天数 × 会话) 降为 O(会话)
        let grouped = Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.startTime) }
        let durationGrouped = Dictionary(grouping: durationSessions) { calendar.startOfDay(for: $0.startTime) }
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
            let dayDurationSessions = durationGrouped[date] ?? []
            let completedCount = daySessions.filter { $0.isCompleted }.count
            // 时长口径：completed + earlyCompleted（提前结束的净专注时长也算进去）
            let totalDuration = dayDurationSessions.filter { $0.countsTowardDuration }.reduce(0) { $0 + $1.actualDuration }

            dailyStats.append(DailyStats(
                date: date,
                completedPomodoros: completedCount,
                totalDuration: totalDuration
            ))
        }

        monthlyData = dailyStats
    }

    // MARK: - Private Methods

    /// 把正计时（TimeRecord）的时长叠加进周/月总和（用户反馈 2026-11-17）。
    /// 番茄数/积分/完成率口径不变：正计时不是番茄，只贡献时长。
    ///
    /// - Parameter records: `refresh()` 一次性拉取的全量记录快照（与标签分布共用，
    ///   避免同一刷新周期内重复全表查询）
    private func applyTimeRecordDurationsToWeeklyAndMonthly(records allRecords: [TimeRecord]) {
        let calendar = Calendar.current
        let today = Date()
        guard let weekStart = calendar.date(byAdding: .day, value: -6, to: today.startOfDay),
              let monthEnd = calendar.date(byAdding: .month, value: 1, to: today.startOfMonth) else { return }
        // 只保留周/月窗口内的记录，按天分组（正计时记录按 startTime 归日）
        let records = allRecords.filter { $0.startTime >= weekStart && $0.startTime < monthEnd }
        let grouped = Dictionary(grouping: records) { calendar.startOfDay(for: $0.startTime) }
        let durationByDay = grouped.mapValues { $0.reduce(0) { $0 + $1.duration } }

        for index in weeklyData.indices where durationByDay[weeklyData[index].date] != nil {
            let d = weeklyData[index]
            weeklyData[index] = DailyStats(
                date: d.date,
                completedPomodoros: d.completedPomodoros,
                totalDuration: d.totalDuration + (durationByDay[d.date] ?? 0)
            )
        }
        for index in monthlyData.indices where durationByDay[monthlyData[index].date] != nil {
            let d = monthlyData[index]
            monthlyData[index] = DailyStats(
                date: d.date,
                completedPomodoros: d.completedPomodoros,
                totalDuration: d.totalDuration + (durationByDay[d.date] ?? 0)
            )
        }
    }

    // MARK: - 时长汇总与标签分布（用户反馈 2026-11-19）

    /// 「未分类」聚合项的固定 id（不依赖任何真实标签，跨次统计稳定）
    static let uncategorizedTagID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))

    /// 重算总时长与五档按标签分布（本周 / 本月 / 今年 / 全部 / 自定义）。
    ///
    /// 口径与「今日专注」一致，避免同一 App 内出现两个时长：
    /// 番茄会话取 completed + earlyCompleted 的净时长；正计时取其落库净时长。
    ///
    /// - Parameters:
    ///   - allForDuration: `refresh()` 一次性拉取的时长口径会话，避免重复全表扫描
    ///   - timeRecords: `refresh()` 一次性拉取的正计时快照（与周/月叠加共用）
    private func computeDurationSummary(allForDuration: [FocusSession], timeRecords: [TimeRecord]) {
        let calendar = Calendar.current
        let today = Date()
        // 「本周」与 weeklyData 同为近 7 天，两处口径必须一致，否则周趋势与本周时长对不上
        let weekStart = calendar.date(byAdding: .day, value: -6, to: today.startOfDay) ?? today.startOfDay
        let monthStart = today.startOfMonth
        let yearStart = today.startOfYear

        // 正计时：进行中的记录 duration 仍为 0，自然被过滤
        let records = timeRecords.filter { $0.duration > 0 }

        weekDuration = sessionSeconds(allForDuration, since: weekStart) + recordSeconds(records, since: weekStart)
        monthDuration = sessionSeconds(allForDuration, since: monthStart) + recordSeconds(records, since: monthStart)
        totalDuration = sessionSeconds(allForDuration, since: nil) + recordSeconds(records, since: nil)

        weekTagDurations = aggregateTagDurations(sessions: allForDuration, records: records,
                                                 from: weekStart, to: nil)
        monthTagDurations = aggregateTagDurations(sessions: allForDuration, records: records,
                                                  from: monthStart, to: nil)
        // 2026-11-22 用户反馈：长周期项目需要直接看到「从开始到现在」的累计，
        // 以及今年 / 自定义区间，档位之间只改区间，聚合判据完全共用。
        yearTagDurations = aggregateTagDurations(sessions: allForDuration, records: records,
                                                 from: yearStart, to: nil)
        allTagDurations = aggregateTagDurations(sessions: allForDuration, records: records,
                                                from: nil, to: nil)

        // 缓存同一份快照：自定义日期变化时只做内存聚合，不重复查 CoreData
        cachedDurationSessions = allForDuration
        cachedDurationRecords = records
        if let customRange {
            customTagDurations = aggregateTagDurations(sessions: allForDuration, records: records,
                                                       from: customRange.start, to: customRange.end)
        }
    }

    /// 按自定义起止日期重算标签分布（2026-11-22 用户反馈）。
    /// 区间为半开区间 `[开始当天 00:00, 结束当天次日 00:00)`，与其余档位边界语义一致。
    func updateCustomTagDurations(start: Date, end: Date) {
        let normalizedStart = start.startOfDay
        let normalizedEnd = end.startOfDay.endOfDay
        guard normalizedStart <= normalizedEnd else { return }
        customRange = (normalizedStart, normalizedEnd)
        customTagDurations = aggregateTagDurations(sessions: cachedDurationSessions,
                                                   records: cachedDurationRecords,
                                                   from: normalizedStart, to: normalizedEnd)
    }

    /// 番茄会话净时长求和（`start == nil` 表示不限时间）
    /// 审查修复 2026-11-22：与 aggregateTagDurations 的 add 守卫保持一致（>0 且有限），
    /// 否则异常时长会让 totalDuration 与 allTagDurations 之和不守恒。
    private func sessionSeconds(_ sessions: [FocusSession], since start: Date?) -> TimeInterval {
        sessions.reduce(0) { total, session in
            guard session.countsTowardDuration else { return total }
            if let start, session.startTime < start { return total }
            let seconds = session.actualDuration
            guard seconds > 0, seconds.isFinite else { return total }
            return total + seconds
        }
    }

    /// 正计时净时长求和（`start == nil` 表示不限时间）
    private func recordSeconds(_ records: [TimeRecord], since start: Date?) -> TimeInterval {
        records.reduce(0) { total, record in
            if let start, record.startTime < start { return total }
            let seconds = record.duration
            guard seconds > 0, seconds.isFinite else { return total }
            return total + seconds
        }
    }

    /// 按标签聚合指定区间内的专注时长（降序 + 占比）。
    ///
    /// 单归属：每条会话 / 记录只落到一个标签，保证「各标签时长之和 == 该区间总时长」。
    /// `from == nil && to == nil` 即「全部 / 累计」，与 `totalDuration` 同口径。
    private func aggregateTagDurations(sessions: [FocusSession],
                                       records: [TimeRecord],
                                       from start: Date?,
                                       to end: Date?) -> [TagDuration] {
        struct Bucket {
            var name: String
            var colorHex: String?
            var seconds: TimeInterval
        }
        var buckets: [UUID: Bucket] = [:]

        func isInRange(_ date: Date) -> Bool {
            if let start, date < start { return false }
            if let end, date >= end { return false }
            return true
        }

        func add(_ tag: Tag?, seconds: TimeInterval) {
            guard seconds > 0, seconds.isFinite else { return }
            let id = tag?.id ?? Self.uncategorizedTagID
            if var bucket = buckets[id] {
                bucket.seconds += seconds
                buckets[id] = bucket
            } else {
                buckets[id] = Bucket(name: tag?.name ?? L10n.shared.未分类,
                                     colorHex: tag?.colorHex,
                                     seconds: seconds)
            }
        }

        for session in sessions where session.countsTowardDuration && isInRange(session.startTime) {
            add(session.resolvedTag, seconds: session.actualDuration)
        }
        for record in records where isInRange(record.startTime) {
            // 正计时：自身标签优先，其次任务首个标签（与 FocusSession.resolvedTag 同判据）
            let tag = record.tag ?? record.task?.tags.sorted { $0.name < $1.name }.first
            add(tag, seconds: record.duration)
        }

        let total = buckets.values.reduce(0) { $0 + $1.seconds }
        guard total > 0 else { return [] }
        return buckets
            .map { id, bucket in
                TagDuration(id: id,
                            name: bucket.name,
                            colorHex: bucket.colorHex,
                            duration: bucket.seconds,
                            ratio: bucket.seconds / total)
            }
            .sorted { $0.duration > $1.duration }
    }

    private func computeTotals(allCompleted: [FocusSession]) {        // 用户反馈 2026-11-17：提前结束（earlyCompleted）的净专注时长也计入今日总和；
        // interrupted / abandoned / running / paused 仍不计入。判据收口在 countsTowardDuration。
        let focusDuration = todaySessions.filter { $0.countsTowardDuration }.reduce(0) { $0 + $1.actualDuration }
        // 正计时（TimeRecord）今日时长并入总和
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: Date())
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? Date()
        let timerDuration = timeRecordService?.getTotalDuration(from: dayStart, to: dayEnd) ?? 0
        todayDuration = focusDuration + timerDuration

        // 计算今日完成率
        let totalCount = todaySessions.count
        let completedCount = todaySessions.filter { $0.isCompleted }.count
        completionRate = totalCount > 0 ? Double(completedCount) / Double(totalCount) : 0

        // 计算累计完成的番茄钟数（复用 refresh() 已拉取的全量结果，避免重复全表扫描）
        totalCompletedPomodoros = allCompleted.count

        // 计算当前连续天数（复用同一次全量结果）
        currentStreak = computeStreak(allCompleted: allCompleted)

        // 派生年热力图（复用同一次全量结果，避免重复扫描）
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

        // 修复（2026-10-14 P2）：口径与 `AchievementService.computeStreak` 统一 ——
        // 今天还没完成时不直接判 0，而是从昨天起算。此前同一天里「统计页连续 0 天」
        // 而「成就已解锁连续 3 天」，两个数字互相打脸。
        if !completedDates.contains(currentDate) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: currentDate) else {
                return 0
            }
            currentDate = yesterday
        }

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

import XCTest
import CoreData
import Combine
@testable import FlowTakt

// MARK: - StatsViewModelTests
// 测试 StatsViewModel：今日数据、周/月统计、累计番茄钟、连续天数、完成率

@MainActor
final class StatsViewModelTests: XCTestCase {
    var persistence: PersistenceController!
    var mockFocusService: MockFocusService!
    var mockTaskService: MockTaskService!
    var viewModel: StatsViewModel!
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        persistence = PersistenceController(inMemory: true)
        mockFocusService = MockFocusService()
        mockTaskService = MockTaskService()
        viewModel = StatsViewModel(
            focusService: mockFocusService,
            taskService: mockTaskService,
            persistenceController: persistence
        )
        cancellables = Set<AnyCancellable>()
    }

    override func tearDown() {
        viewModel = nil
        mockTaskService = nil
        mockFocusService = nil
        persistence = nil
        cancellables = nil
        super.tearDown()
    }

    // ========================================================================
    // MARK: - 初始状态
    // ========================================================================

    func testInitialState_WhenCreated_ThenAllDataIsEmpty() {
        XCTAssertTrue(viewModel.todaySessions.isEmpty, "初始今日会话应为空")
        // init 会调用 refresh()，fetchWeeklyData/fetchMonthlyData 会生成空值条目
        XCTAssertEqual(viewModel.weeklyData.count, 7, "周数据应有 7 天条目")
        let calendar = Calendar.current
        let daysInMonth = calendar.range(of: .day, in: .month, for: Date())!.count
        XCTAssertEqual(viewModel.monthlyData.count, daysInMonth, "月数据天数应与当月一致")
        XCTAssertEqual(viewModel.totalCompletedPomodoros, 0)
        XCTAssertEqual(viewModel.currentStreak, 0)
        XCTAssertEqual(viewModel.todayDuration, 0)
        XCTAssertEqual(viewModel.completionRate, 0)
    }

    // ========================================================================
    // MARK: - 刷新 (Refresh)
    // ========================================================================

    func testRefresh_WhenCalled_ThenUpdatesFromFocusService() {
        // Given: 创建今日已完成会话
        let context = persistence.viewContext
        let session = FocusSession(context: context)
        session.id = UUID()
        session.startTime = Date()
        session.plannedDuration = 1500
        session.actualDuration = 1500
        session.status = SessionStatus.completed.rawValue
        session.phase = FocusPhase.focus.rawValue
        session.earnedPoints = 10
        session.roundIndex = 1
        session.createdAt = Date()
        try? context.save()

        mockFocusService.sessions = [session]

        // When
        viewModel.refresh()

        // Then
        XCTAssertEqual(viewModel.todaySessions.count, 1)
        XCTAssertEqual(viewModel.todaySessions.first?.status, SessionStatus.completed.rawValue)
        XCTAssertEqual(viewModel.totalCompletedPomodoros, 1)
        XCTAssertEqual(viewModel.todayDuration, 1500)
    }

    func testRefresh_WithMultipleSessions_ThenTodaySessionsCountIsCorrect() {
        // Given
        let context = persistence.viewContext
        for i in 0..<3 {
            let session = FocusSession(context: context)
            session.id = UUID()
            session.startTime = Date()
            session.plannedDuration = 1500
            session.actualDuration = 1500
            session.status = SessionStatus.completed.rawValue
            session.phase = FocusPhase.focus.rawValue
            session.earnedPoints = 10
            session.roundIndex = Int16(i + 1)
            session.createdAt = Date()
        }
        try? context.save()
        mockFocusService.sessions = Array(persistence.viewContext.registeredObjects.compactMap { $0 as? FocusSession })

        // When
        viewModel.refresh()

        // Then
        XCTAssertEqual(viewModel.todaySessions.count, 3)
        XCTAssertEqual(viewModel.totalCompletedPomodoros, 3)
    }

    // ========================================================================
    // MARK: - 今日完成率
    // ========================================================================

    func testCompletionRate_WhenAllCompleted_ThenRateIsOne() {
        // Given
        let context = persistence.viewContext
        for _ in 0..<2 {
            let session = FocusSession(context: context)
            session.id = UUID()
            session.startTime = Date()
            session.plannedDuration = 1500
            session.actualDuration = 1500
            session.status = SessionStatus.completed.rawValue
            session.phase = FocusPhase.focus.rawValue
            session.earnedPoints = 10
            session.roundIndex = 1
            session.createdAt = Date()
        }
        try? context.save()
        mockFocusService.sessions = Array(persistence.viewContext.registeredObjects.compactMap { $0 as? FocusSession })

        // When
        viewModel.refresh()

        // Then
        XCTAssertEqual(viewModel.completionRate, 1.0, accuracy: 0.01)
    }

    func testCompletionRate_WhenMixed_ThenRateIsProportional() {
        // Given: 1 完成 + 1 中断 = 50%
        let context = persistence.viewContext
        let completed = FocusSession(context: context)
        completed.id = UUID()
        completed.startTime = Date()
        completed.plannedDuration = 1500
        completed.actualDuration = 1500
        completed.status = SessionStatus.completed.rawValue
        completed.phase = FocusPhase.focus.rawValue
        completed.earnedPoints = 10
        completed.roundIndex = 1
        completed.createdAt = Date()

        let interrupted = FocusSession(context: context)
        interrupted.id = UUID()
        interrupted.startTime = Date()
        interrupted.plannedDuration = 1500
        interrupted.actualDuration = 600
        interrupted.status = SessionStatus.interrupted.rawValue
        interrupted.phase = FocusPhase.focus.rawValue
        interrupted.earnedPoints = 0
        interrupted.roundIndex = 2
        interrupted.createdAt = Date()
        try? context.save()
        mockFocusService.sessions = [completed, interrupted]

        // When
        viewModel.refresh()

        // Then
        XCTAssertEqual(viewModel.completionRate, 0.5, accuracy: 0.01)
    }

    func testCompletionRate_WhenNoSessions_ThenRateIsZero() {
        // When
        viewModel.refresh()

        // Then
        XCTAssertEqual(viewModel.completionRate, 0)
    }

    // ========================================================================
    // MARK: - 今日时长
    // ========================================================================

    func testTodayDuration_SumsOnlyCompletedSessionActualDurations() {
        // Given
        let context = persistence.viewContext
        let s1 = FocusSession(context: context)
        s1.id = UUID()
        s1.startTime = Date()
        s1.plannedDuration = 1500
        s1.actualDuration = 1500
        s1.status = SessionStatus.completed.rawValue
        s1.phase = FocusPhase.focus.rawValue
        s1.earnedPoints = 10
        s1.roundIndex = 1
        s1.createdAt = Date()

        let s2 = FocusSession(context: context)
        s2.id = UUID()
        s2.startTime = Date()
        s2.plannedDuration = 1500
        s2.actualDuration = 900
        s2.status = SessionStatus.interrupted.rawValue
        s2.phase = FocusPhase.focus.rawValue
        s2.earnedPoints = 0
        s2.roundIndex = 2
        s2.createdAt = Date()
        try? context.save()
        mockFocusService.sessions = [s1, s2]

        // When
        viewModel.refresh()

        // Then - 今日总时长只统计已完成会话（interrupted 不计入，避免统计虚高）
        XCTAssertEqual(viewModel.todayDuration, 1500)
    }

    // ========================================================================
    // MARK: - 连续天数 (Streak)
    // ========================================================================

    func testCurrentStreak_WhenNoSessions_ThenZero() {
        viewModel.refresh()
        XCTAssertEqual(viewModel.currentStreak, 0)
    }

    func testCurrentStreak_WithConsecutiveDays_ThenPositive() {
        // Given: 今天 + 昨天已完成
        let context = persistence.viewContext
        let calendar = Calendar.current

        let today = FocusSession(context: context)
        today.id = UUID()
        today.startTime = Date()
        today.plannedDuration = 1500
        today.actualDuration = 1500
        today.status = SessionStatus.completed.rawValue
        today.phase = FocusPhase.focus.rawValue
        today.earnedPoints = 10
        today.roundIndex = 1
        today.createdAt = Date()

        let yesterday = FocusSession(context: context)
        yesterday.id = UUID()
        yesterday.startTime = calendar.date(byAdding: .day, value: -1, to: Date())!
        yesterday.plannedDuration = 1500
        yesterday.actualDuration = 1500
        yesterday.status = SessionStatus.completed.rawValue
        yesterday.phase = FocusPhase.focus.rawValue
        yesterday.earnedPoints = 10
        yesterday.roundIndex = 1
        yesterday.createdAt = Date()
        try? context.save()
        // 统计改走 FocusService（Mock 需提供已完成会话数据）
        mockFocusService.sessions = [today, yesterday]

        // When
        viewModel.refresh()

        // Then: streak 至少 ≥ 1
        XCTAssertGreaterThanOrEqual(viewModel.currentStreak, 1, "连续天数应至少为 1")
    }

    // ========================================================================
    // MARK: - 周数据
    // ========================================================================

    func testWeeklyData_WhenCalled_ThenReturnsLast7Days() {
        // Given: focusService 返回今日已完成会话
        let context = persistence.viewContext
        let session = FocusSession(context: context)
        session.id = UUID()
        session.startTime = Date()
        session.plannedDuration = 1500
        session.actualDuration = 1500
        session.status = SessionStatus.completed.rawValue
        session.phase = FocusPhase.focus.rawValue
        session.earnedPoints = 10
        session.roundIndex = 1
        session.createdAt = Date()
        try? context.save()
        mockFocusService.sessions = [session]

        // When
        viewModel.fetchWeeklyData()

        // Then
        XCTAssertEqual(viewModel.weeklyData.count, 7, "周数据应包含 7 天")
        // 最后一天（今天）应有数据
        let todayStat = viewModel.weeklyData.last!
        XCTAssertGreaterThanOrEqual(todayStat.completedPomodoros, 1)
    }

    // ========================================================================
    // MARK: - 月数据
    // ========================================================================

    func testMonthlyData_WhenCalled_ThenReturnsCurrentMonthDays() {
        let context = persistence.viewContext
        let session = FocusSession(context: context)
        session.id = UUID()
        session.startTime = Date()
        session.plannedDuration = 1500
        session.actualDuration = 1500
        session.status = SessionStatus.completed.rawValue
        session.phase = FocusPhase.focus.rawValue
        session.earnedPoints = 10
        session.roundIndex = 1
        session.createdAt = Date()
        try? context.save()

        // When
        viewModel.fetchMonthlyData()

        // Then
        let calendar = Calendar.current
        let range = calendar.range(of: .day, in: .month, for: Date())!
        XCTAssertEqual(viewModel.monthlyData.count, range.count, "月数据天数应与当月天数一致")
    }

    // ========================================================================
    // MARK: - Published 属性发布
    // ========================================================================

    func testPublishedTotalCompletedPomodoros_WhenRefreshed_ThenPublishesUpdate() {
        let context = persistence.viewContext
        for _ in 0..<3 {
            let session = FocusSession(context: context)
            session.id = UUID()
            session.startTime = Date()
            session.plannedDuration = 1500
            session.actualDuration = 1500
            session.status = SessionStatus.completed.rawValue
            session.phase = FocusPhase.focus.rawValue
            session.earnedPoints = 10
            session.roundIndex = 1
            session.createdAt = Date()
        }
        try? context.save()
        mockFocusService.sessions = Array(persistence.viewContext.registeredObjects.compactMap { $0 as? FocusSession })

        let expectation = expectation(description: "totalCompletedPomodoros 发布更新")

        viewModel.$totalCompletedPomodoros
            .dropFirst()
            .sink { value in
                if value == 3 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        viewModel.refresh()

        wait(for: [expectation], timeout: 1.0)
    }

    // ========================================================================
    // MARK: - 数据库重置处理
    // ========================================================================

    func testDatabaseWillReset_ClearsAllData() {
        // Given: 先填充数据
        let context = persistence.viewContext
        let session = FocusSession(context: context)
        session.id = UUID()
        session.startTime = Date()
        session.plannedDuration = 1500
        session.actualDuration = 1500
        session.status = SessionStatus.completed.rawValue
        session.phase = FocusPhase.focus.rawValue
        session.earnedPoints = 10
        session.roundIndex = 1
        session.createdAt = Date()
        try? context.save()
        mockFocusService.sessions = [session]
        viewModel.refresh()
        XCTAssertEqual(viewModel.totalCompletedPomodoros, 1)

        // When
        NotificationCenter.default.post(name: .databaseWillReset, object: nil)

        // Then
        XCTAssertTrue(viewModel.todaySessions.isEmpty)
        XCTAssertTrue(viewModel.weeklyData.isEmpty)
        XCTAssertTrue(viewModel.monthlyData.isEmpty)
        XCTAssertEqual(viewModel.totalCompletedPomodoros, 0)
        XCTAssertEqual(viewModel.currentStreak, 0)
        XCTAssertEqual(viewModel.todayDuration, 0)
        XCTAssertEqual(viewModel.completionRate, 0)
    }

    // ========================================================================
    // MARK: - 边界条件
    // ========================================================================

    func testRefresh_MultipleCalls_AlwaysReturnsLatestData() {
        let context = persistence.viewContext
        let s1 = FocusSession(context: context)
        s1.id = UUID()
        s1.startTime = Date()
        s1.plannedDuration = 1500
        s1.actualDuration = 1500
        s1.status = SessionStatus.completed.rawValue
        s1.phase = FocusPhase.focus.rawValue
        s1.earnedPoints = 10
        s1.roundIndex = 1
        s1.createdAt = Date()
        try? context.save()
        mockFocusService.sessions = [s1]

        viewModel.refresh()
        XCTAssertEqual(viewModel.totalCompletedPomodoros, 1)

        let s2 = FocusSession(context: context)
        s2.id = UUID()
        s2.startTime = Date()
        s2.plannedDuration = 1500
        s2.actualDuration = 1500
        s2.status = SessionStatus.completed.rawValue
        s2.phase = FocusPhase.focus.rawValue
        s2.earnedPoints = 10
        s2.roundIndex = 2
        s2.createdAt = Date()
        try? context.save()
        mockFocusService.sessions = [s1, s2]

        viewModel.refresh()
        XCTAssertEqual(viewModel.totalCompletedPomodoros, 2)
    }

    // ========================================================================
    // MARK: - 中断洞察（今日中断次数 / 最近原因）
    // ========================================================================

    func testTodayInterruptedCount_GivenAbandonedSessions_ThenCountsOnlyAbandoned() {
        // Given
        let context = persistence.viewContext
        let abandoned = FocusSession(context: context)
        abandoned.id = UUID()
        abandoned.startTime = Date()
        abandoned.status = SessionStatus.abandoned.rawValue
        abandoned.interruptionReason = "电话"
        abandoned.phase = FocusPhase.focus.rawValue
        abandoned.earnedPoints = 0
        abandoned.createdAt = Date()
        abandoned.updatedAt = Date()

        let completed = FocusSession(context: context)
        completed.id = UUID()
        completed.startTime = Date()
        completed.status = SessionStatus.completed.rawValue
        completed.phase = FocusPhase.focus.rawValue
        completed.earnedPoints = 10
        completed.createdAt = Date()
        completed.updatedAt = Date()
        try? context.save()
        mockFocusService.sessions = [abandoned, completed]

        // When
        viewModel.refresh()

        // Then - 只统计 abandoned 会话，且取最近一次原因
        XCTAssertEqual(viewModel.todayInterruptedCount, 1, "今日中断次数只统计 abandoned 会话")
        XCTAssertEqual(viewModel.lastInterruptionReason, "电话")
    }

    func testTodayInterruptedCount_NoAbandoned_ThenZeroAndNilReason() {
        // Given - 无放弃会话
        let context = persistence.viewContext
        let completed = FocusSession(context: context)
        completed.id = UUID()
        completed.startTime = Date()
        completed.status = SessionStatus.completed.rawValue
        completed.phase = FocusPhase.focus.rawValue
        completed.earnedPoints = 10
        completed.createdAt = Date()
        completed.updatedAt = Date()
        try? context.save()
        mockFocusService.sessions = [completed]

        // When
        viewModel.refresh()

        // Then
        XCTAssertEqual(viewModel.todayInterruptedCount, 0)
        XCTAssertNil(viewModel.lastInterruptionReason)
    }

    // ========================================================================
    // MARK: - 年热力图数据（A5）
    // ========================================================================

    func testYearlyCounts_GivenSessionsThisYear_ThenAggregatesByDay() {
        // Given - 今天完成 1 个 + 昨天完成 2 个 + 一年多前的（应排除）
        let context = persistence.viewContext
        let calendar = Calendar.current
        let today = FocusSession(context: context)
        today.id = UUID()
        today.startTime = Date()
        today.status = SessionStatus.completed.rawValue
        today.actualDuration = 1500
        today.earnedPoints = 10
        today.createdAt = Date()
        today.updatedAt = Date()

        let yesterday1 = FocusSession(context: context)
        yesterday1.id = UUID()
        yesterday1.startTime = calendar.date(byAdding: .day, value: -1, to: Date())!
        yesterday1.status = SessionStatus.completed.rawValue
        yesterday1.actualDuration = 1500
        yesterday1.earnedPoints = 10
        yesterday1.createdAt = Date()
        yesterday1.updatedAt = Date()

        let yesterday2 = FocusSession(context: context)
        yesterday2.id = UUID()
        yesterday2.startTime = calendar.date(byAdding: .day, value: -1, to: Date())!
        yesterday2.status = SessionStatus.completed.rawValue
        yesterday2.actualDuration = 1500
        yesterday2.earnedPoints = 10
        yesterday2.createdAt = Date()
        yesterday2.updatedAt = Date()

        let tooOld = FocusSession(context: context)
        tooOld.id = UUID()
        tooOld.startTime = calendar.date(byAdding: .year, value: -2, to: Date())!
        tooOld.status = SessionStatus.completed.rawValue
        tooOld.actualDuration = 1500
        tooOld.earnedPoints = 10
        tooOld.createdAt = Date()
        tooOld.updatedAt = Date()
        try? context.save()
        mockFocusService.sessions = [today, yesterday1, yesterday2, tooOld]

        // When
        viewModel.refresh()

        // Then - 按天聚合，仅统计一年内
        let todayKey = calendar.startOfDay(for: Date())
        let yesterdayKey = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -1, to: Date())!)
        XCTAssertEqual(viewModel.yearlyCounts[todayKey], 1, "今日 1 个完成")
        XCTAssertEqual(viewModel.yearlyCounts[yesterdayKey], 2, "昨日 2 个完成应累加")
        XCTAssertEqual(viewModel.yearlyTotalDays, 2, "一年内有记录的天数为 2（老数据被排除）")
    }
}

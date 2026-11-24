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
        // 2026-11-22 扩展档位初始均为空
        XCTAssertTrue(viewModel.yearTagDurations.isEmpty)
        XCTAssertTrue(viewModel.allTagDurations.isEmpty)
        XCTAssertTrue(viewModel.customTagDurations.isEmpty)
    }

    // ========================================================================
    // MARK: - 刷新 (Refresh)
    // ========================================================================

    func testRefresh_WhenCalled_ThenUpdatesFromFocusService() {
        // Given: 创建今日已完成会话
        let context = persistence.viewContext
        let session = FocusSession(context: context)
        session.storageId = UUID()
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
            session.storageId = UUID()
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
            session.storageId = UUID()
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
        completed.storageId = UUID()
        completed.startTime = Date()
        completed.plannedDuration = 1500
        completed.actualDuration = 1500
        completed.status = SessionStatus.completed.rawValue
        completed.phase = FocusPhase.focus.rawValue
        completed.earnedPoints = 10
        completed.roundIndex = 1
        completed.createdAt = Date()

        let interrupted = FocusSession(context: context)
        interrupted.storageId = UUID()
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
        s1.storageId = UUID()
        s1.startTime = Date()
        s1.plannedDuration = 1500
        s1.actualDuration = 1500
        s1.status = SessionStatus.completed.rawValue
        s1.phase = FocusPhase.focus.rawValue
        s1.earnedPoints = 10
        s1.roundIndex = 1
        s1.createdAt = Date()

        let s2 = FocusSession(context: context)
        s2.storageId = UUID()
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
        today.storageId = UUID()
        today.startTime = Date()
        today.plannedDuration = 1500
        today.actualDuration = 1500
        today.status = SessionStatus.completed.rawValue
        today.phase = FocusPhase.focus.rawValue
        today.earnedPoints = 10
        today.roundIndex = 1
        today.createdAt = Date()

        let yesterday = FocusSession(context: context)
        yesterday.storageId = UUID()
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
        session.storageId = UUID()
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
        session.storageId = UUID()
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
            session.storageId = UUID()
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
        session.storageId = UUID()
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
        XCTAssertTrue(viewModel.yearTagDurations.isEmpty)
        XCTAssertTrue(viewModel.allTagDurations.isEmpty)
        XCTAssertTrue(viewModel.customTagDurations.isEmpty)
    }

    // ========================================================================
    // MARK: - 边界条件
    // ========================================================================

    func testRefresh_MultipleCalls_AlwaysReturnsLatestData() {
        let context = persistence.viewContext
        let s1 = FocusSession(context: context)
        s1.storageId = UUID()
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
        s2.storageId = UUID()
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
        abandoned.storageId = UUID()
        abandoned.startTime = Date()
        abandoned.status = SessionStatus.abandoned.rawValue
        abandoned.interruptionReason = "电话"
        abandoned.phase = FocusPhase.focus.rawValue
        abandoned.earnedPoints = 0
        abandoned.createdAt = Date()
        abandoned.updatedAt = Date()

        let completed = FocusSession(context: context)
        completed.storageId = UUID()
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
        completed.storageId = UUID()
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
        today.storageId = UUID()
        today.startTime = Date()
        today.status = SessionStatus.completed.rawValue
        today.actualDuration = 1500
        today.earnedPoints = 10
        today.createdAt = Date()
        today.updatedAt = Date()

        let yesterday1 = FocusSession(context: context)
        yesterday1.storageId = UUID()
        yesterday1.startTime = calendar.date(byAdding: .day, value: -1, to: Date())!
        yesterday1.status = SessionStatus.completed.rawValue
        yesterday1.actualDuration = 1500
        yesterday1.earnedPoints = 10
        yesterday1.createdAt = Date()
        yesterday1.updatedAt = Date()

        let yesterday2 = FocusSession(context: context)
        yesterday2.storageId = UUID()
        yesterday2.startTime = calendar.date(byAdding: .day, value: -1, to: Date())!
        yesterday2.status = SessionStatus.completed.rawValue
        yesterday2.actualDuration = 1500
        yesterday2.earnedPoints = 10
        yesterday2.createdAt = Date()
        yesterday2.updatedAt = Date()

        let tooOld = FocusSession(context: context)
        tooOld.storageId = UUID()
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

    // ========================================================================
    // MARK: - 提前结束计入时长但不计入番茄（用户反馈 2026-11-17）
    // ========================================================================

    func testTodayDuration_GivenEarlyCompleted_ThenTimeCountedButPomodoroNot() {
        // Given - 1 个正常完成 1500 秒 + 1 个提前结束 300 秒
        let context = persistence.viewContext
        let completed = FocusSession(context: context)
        completed.storageId = UUID()
        completed.startTime = Date().addingTimeInterval(-600)
        completed.plannedDuration = 1500
        completed.actualDuration = 1500
        completed.status = SessionStatus.completed.rawValue
        completed.phase = FocusPhase.focus.rawValue
        completed.earnedPoints = 10
        completed.roundIndex = 1
        completed.createdAt = Date()

        let early = FocusSession(context: context)
        early.storageId = UUID()
        early.startTime = Date().addingTimeInterval(-300)
        early.plannedDuration = 1500
        early.actualDuration = 300
        early.status = SessionStatus.earlyCompleted.rawValue
        early.phase = FocusPhase.focus.rawValue
        early.earnedPoints = 0
        early.roundIndex = 2
        early.createdAt = Date()
        try? context.save()
        mockFocusService.sessions = [completed, early]

        // When
        viewModel.refresh()

        // Then - 时长合计 1800；完成番茄仍只 1 个；完成率 0.5；积分只算完成
        XCTAssertEqual(viewModel.todayDuration, 1800, "提前结束的净时长应计入今日总和")
        XCTAssertEqual(viewModel.totalCompletedPomodoros, 1, "提前结束不算完成番茄")
        XCTAssertEqual(viewModel.completionRate, 0.5, accuracy: 0.01)
    }

    func testWeeklyAndMonthlyDuration_GivenEarlyCompleted_ThenIncluded() {
        // Given - 今日提前结束 300 秒
        let context = persistence.viewContext
        let early = FocusSession(context: context)
        early.storageId = UUID()
        early.startTime = Date()
        early.plannedDuration = 1500
        early.actualDuration = 300
        early.status = SessionStatus.earlyCompleted.rawValue
        early.phase = FocusPhase.focus.rawValue
        early.earnedPoints = 0
        early.createdAt = Date()
        early.updatedAt = Date()
        try? context.save()
        mockFocusService.sessions = [early]

        // When
        viewModel.refresh()

        // Then - 周/月时长应含提前结束，番茄数仍为 0
        let todayKey = Calendar.current.startOfDay(for: Date())
        XCTAssertEqual(viewModel.weeklyData.last?.totalDuration, 300)
        XCTAssertEqual(viewModel.weeklyData.last?.completedPomodoros, 0)
        let todayIndex = Calendar.current.component(.day, from: Date()) - 1
        XCTAssertEqual(viewModel.monthlyData[todayIndex].totalDuration, 300)
        XCTAssertEqual(viewModel.monthlyData[todayIndex].completedPomodoros, 0)
        _ = todayKey
    }

    // ========================================================================
    // MARK: - 正计时时长计入总和（用户反馈 2026-11-17）
    // ========================================================================

    func testTodayDuration_GivenTimeRecords_ThenTimerDurationIncluded() {
        // Given - 专注 1500 秒 + 正计时 600 秒（今日）
        let context = persistence.viewContext
        let session = FocusSession(context: context)
        session.storageId = UUID()
        session.startTime = Date()
        session.plannedDuration = 1500
        session.actualDuration = 1500
        session.status = SessionStatus.completed.rawValue
        session.phase = FocusPhase.focus.rawValue
        session.earnedPoints = 10
        session.createdAt = Date()
        let timerRecord = TimeRecord(context: context)
        timerRecord.storageId = UUID()
        timerRecord.startTime = Date()
        timerRecord.duration = 600
        timerRecord.createdAt = Date()
        timerRecord.updatedAt = Date()
        try? context.save()
        mockFocusService.sessions = [session]

        let mockTimer = MockTimeRecordService()
        mockTimer.records = [timerRecord]
        mockTimer.totalDurationToReturn = 600  // getTotalDuration 由 Mock 直接返回配置值
        let vmWithTimer = StatsViewModel(
            focusService: mockFocusService,
            taskService: mockTaskService,
            persistenceController: persistence,
            timeRecordService: mockTimer
        )

        // Then - 今日总和 = 1500（专注）+ 600（正计时）
        XCTAssertEqual(vmWithTimer.todayDuration, 2100, "正计时时长应计入今日总和")
        XCTAssertEqual(vmWithTimer.totalCompletedPomodoros, 1, "正计时不算番茄")
    }

    func testInterruptionInsight_GivenEarlyCompletedWithReason_ThenReasonKept() {
        // Given - 提前结束会话带中断原因
        let context = persistence.viewContext
        let early = FocusSession(context: context)
        early.storageId = UUID()
        early.startTime = Date()
        early.plannedDuration = 1500
        early.actualDuration = 300
        early.status = SessionStatus.earlyCompleted.rawValue
        early.phase = FocusPhase.focus.rawValue
        early.interruptionReason = "临时有事"
        early.earnedPoints = 0
        early.createdAt = Date()
        early.updatedAt = Date()
        try? context.save()
        mockFocusService.sessions = [early]

        // When
        viewModel.refresh()

        // Then - 提前结束仍计入中断洞察，原因不丢失
        XCTAssertEqual(viewModel.todayInterruptedCount, 1)
        XCTAssertEqual(viewModel.lastInterruptionReason, "临时有事")
    }

    func testLastInterruptionReason_GivenLatestWithoutReason_ThenFallsBackToEarlierWithReason() {
        // Given - 两次提前结束：较早一次带原因「临时有事」，最近一次无原因（单击停止默认路径）
        let context = persistence.viewContext
        let earlier = FocusSession(context: context)
        earlier.storageId = UUID()
        earlier.startTime = Date().addingTimeInterval(-600)
        earlier.plannedDuration = 1500
        earlier.actualDuration = 200
        earlier.status = SessionStatus.earlyCompleted.rawValue
        earlier.phase = FocusPhase.focus.rawValue
        earlier.interruptionReason = "临时有事"
        earlier.createdAt = Date().addingTimeInterval(-600)
        earlier.updatedAt = Date().addingTimeInterval(-590)

        let latest = FocusSession(context: context)
        latest.storageId = UUID()
        latest.startTime = Date().addingTimeInterval(-100)
        latest.plannedDuration = 1500
        latest.actualDuration = 60
        latest.status = SessionStatus.earlyCompleted.rawValue
        latest.phase = FocusPhase.focus.rawValue
        latest.interruptionReason = nil
        latest.createdAt = Date().addingTimeInterval(-100)
        latest.updatedAt = Date()
        try? context.save()
        mockFocusService.sessions = [earlier, latest]

        // When
        viewModel.refresh()

        // Then - 应返回较早那条带原因的记录，而非因最近一条无原因而丢失
        XCTAssertEqual(viewModel.todayInterruptedCount, 2)
        XCTAssertEqual(viewModel.lastInterruptionReason, "临时有事",
                       "最近一次无原因不得覆盖此前明确填写的中断原因")
    }

    // ========================================================================
    // MARK: - 总时长汇总与标签分布（用户反馈 2026-11-19）
    // ========================================================================

    /// 三档总时长：提前结束的净时长必须计入，历史会话计入累计
    func testDurationSummary_IncludesEarlyCompletedAndHistoricalSessions() {
        // Given
        let context = persistence.viewContext
        let now = Date()
        let calendar = Calendar.current

        let todayEarly = makeSession(in: context, start: now, actual: 600,
                                     status: .earlyCompleted, tag: nil)
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: now) ?? now
        let thisWeek = makeSession(in: context, start: twoDaysAgo, actual: 900,
                                   status: .completed, tag: nil)
        let lastMonth = calendar.date(byAdding: .month, value: -1, to: now) ?? now
        let older = makeSession(in: context, start: lastMonth, actual: 1200,
                                status: .completed, tag: nil)
        try? context.save()
        mockFocusService.sessions = [todayEarly, thisWeek, older]

        // When
        viewModel.refresh()

        // Then
        XCTAssertEqual(viewModel.todayDuration, 600, accuracy: 0.5,
                       "提前结束的净时长计入今日")
        XCTAssertEqual(viewModel.weekDuration, 1500, accuracy: 0.5,
                       "近 7 天包含今日提前结束 + 两天前完成")
        XCTAssertEqual(viewModel.totalDuration, 2700, accuracy: 0.5,
                       "累计包含全部历史")
        // 月初运行时「两天前」可能落到上月，故只断言下界
        XCTAssertGreaterThanOrEqual(viewModel.monthDuration, 600)
    }

    /// 标签分布：按标签聚合、单归属守恒、未分类不隐瞒
    func testTagDurations_GroupedByTagWithConservedTotal() {
        // Given
        let context = persistence.viewContext
        let work = Tag(context: context)
        work.storageId = UUID()
        work.name = "工作"
        work.colorHex = "#4CAF50"
        work.createdAt = Date()

        let study = Tag(context: context)
        study.storageId = UUID()
        study.name = "学习"
        study.colorHex = "#2196F3"
        study.createdAt = Date()

        let s1 = makeSession(in: context, start: Date(), actual: 600, status: .completed, tag: work)
        let s2 = makeSession(in: context, start: Date(), actual: 300, status: .earlyCompleted, tag: study)
        let s3 = makeSession(in: context, start: Date(), actual: 100, status: .completed, tag: nil)
        try? context.save()
        mockFocusService.sessions = [s1, s2, s3]

        // When
        viewModel.refresh()

        // Then
        let entries = viewModel.monthTagDurations
        XCTAssertEqual(entries.count, 3, "两个标签 + 未分类")
        XCTAssertEqual(entries.first?.name, "工作", "按时长降序，最长在前")
        XCTAssertEqual(entries.first?.duration ?? 0, 600, accuracy: 0.5)
        XCTAssertEqual(entries.first?.colorHex, "#4CAF50", "保留标签自定义颜色")

        let sum = entries.reduce(0) { $0 + $1.duration }
        XCTAssertEqual(sum, viewModel.monthDuration, accuracy: 0.5,
                       "各标签时长之和必须等于总时长（单归属守恒）")

        let ratioSum = entries.reduce(0) { $0 + $1.ratio }
        XCTAssertEqual(ratioSum, 1.0, accuracy: 0.001)

        XCTAssertTrue(entries.contains { $0.name == L10n.shared.未分类 },
                      "无标签的会话计入「未分类」，不得丢弃")
    }

    /// 正计时记录计入总时长与标签分布（无标签时归入未分类）
    func testDurationSummary_IncludesStopwatchRecords() {
        // Given
        let context = persistence.viewContext
        let record = TimeRecord(context: context)
        record.storageId = UUID()
        record.startTime = Date()
        record.endTime = Date()
        record.duration = 1200
        record.pausedDuration = 0
        record.createdAt = Date()
        record.updatedAt = Date()
        try? context.save()

        let mockTimeRecord = MockTimeRecordService()
        mockTimeRecord.records = [record]
        // computeTotals 走 getTotalDuration（今日口径），本条测试固定返回同一净时长
        mockTimeRecord.totalDurationToReturn = 1200

        let vm = StatsViewModel(
            focusService: mockFocusService,
            taskService: mockTaskService,
            persistenceController: persistence,
            timeRecordService: mockTimeRecord
        )

        // Then
        XCTAssertEqual(vm.todayDuration, 1200, accuracy: 0.5)
        XCTAssertEqual(vm.weekDuration, 1200, accuracy: 0.5)
        XCTAssertEqual(vm.totalDuration, 1200, accuracy: 0.5)
        XCTAssertEqual(vm.monthTagDurations.first?.name, L10n.shared.未分类)
        XCTAssertEqual(vm.monthTagDurations.first?.duration ?? 0, 1200, accuracy: 0.5)
    }

    /// 2026-11-22 用户反馈：长周期项目要看「全部 / 年」档，跨年历史只进全部，不进今年
    func testTagDurations_AllAndYearRanges_CoverLongProjects() {
        let context = persistence.viewContext
        let tag = Tag(context: context)
        tag.storageId = UUID()
        tag.name = "长期项目"
        tag.colorHex = "#FF5722"
        tag.createdAt = Date()

        let calendar = Calendar.current
        let today = Date()
        let yearStart = today.startOfYear
        let inYear = max(yearStart, calendar.date(byAdding: .day, value: -30, to: today) ?? today)
        let beforeYear = calendar.date(byAdding: .day, value: -1, to: yearStart)
            ?? yearStart.addingTimeInterval(-86_400)

        let s1 = makeSession(in: context, start: today, actual: 600, status: .completed, tag: tag)
        let s2 = makeSession(in: context, start: inYear, actual: 300, status: .earlyCompleted, tag: tag)
        let s3 = makeSession(in: context, start: beforeYear, actual: 900, status: .completed, tag: tag)
        try? context.save()
        mockFocusService.sessions = [s1, s2, s3]

        viewModel.refresh()

        XCTAssertEqual(viewModel.allTagDurations.first?.duration ?? 0, 1800, accuracy: 0.5,
                       "全部档包含跨年全部历史")
        XCTAssertEqual(viewModel.yearTagDurations.first?.duration ?? 0, 900, accuracy: 0.5,
                       "今年档只含今年起点之后的时长")
        XCTAssertEqual(viewModel.allTagDurations.first?.duration ?? 0,
                       viewModel.totalDuration, accuracy: 0.5,
                       "全部档按标签之和与累计总时长守恒")
        // 同一标签在「全部」占跨年总量的一半，在「今年」占全部 —— 两档 ratio 必须各自独立计算
        XCTAssertEqual(viewModel.allTagDurations.first?.ratio ?? 0, 0.5, accuracy: 0.001,
                       "全部档占比按跨年总量计算")
        XCTAssertEqual(viewModel.yearTagDurations.first?.ratio ?? 0, 1.0, accuracy: 0.001,
                       "今年档占比只按今年总量计算")
    }

    /// 自定义区间：用缓存快照即时重算，refresh 后保留用户所选区间
    func testCustomTagDurations_UsesSelectedRangeAndSurvivesRefresh() {
        let context = persistence.viewContext
        let tag = Tag(context: context)
        tag.storageId = UUID()
        tag.name = "自定义区间"
        tag.createdAt = Date()

        let calendar = Calendar.current
        let today = Date()
        let inRange = calendar.date(byAdding: .day, value: -40, to: today) ?? today
        let tooOld = calendar.date(byAdding: .day, value: -60, to: today) ?? today
        let start = calendar.date(byAdding: .day, value: -50, to: today) ?? today
        let end = calendar.date(byAdding: .day, value: -30, to: today) ?? today

        let s1 = makeSession(in: context, start: today, actual: 600, status: .completed, tag: tag)
        let s2 = makeSession(in: context, start: inRange, actual: 300, status: .completed, tag: tag)
        let s3 = makeSession(in: context, start: tooOld, actual: 900, status: .completed, tag: tag)
        try? context.save()
        mockFocusService.sessions = [s1, s2, s3]

        viewModel.refresh()
        XCTAssertTrue(viewModel.customTagDurations.isEmpty, "未选区间前自定义档为空")

        viewModel.updateCustomTagDurations(start: start, end: end)
        XCTAssertEqual(viewModel.customTagDurations.first?.duration ?? 0, 300, accuracy: 0.5,
                       "只统计落在自定义区间内的记录")

        viewModel.refresh()
        XCTAssertEqual(viewModel.customTagDurations.first?.duration ?? 0, 300, accuracy: 0.5,
                       "数据库刷新后仍按用户所选区间统计")

        viewModel.updateCustomTagDurations(start: end, end: start)
        XCTAssertEqual(viewModel.customTagDurations.first?.duration ?? 0, 300, accuracy: 0.5,
                       "起止倒置时忽略，不把数据清空")
    }

    // MARK: - Helpers

    private func makeSession(in context: NSManagedObjectContext,
                             start: Date,
                             actual: TimeInterval,
                             status: SessionStatus,
                             tag: Tag?) -> FocusSession {
        let session = FocusSession(context: context)
        session.storageId = UUID()
        session.startTime = start
        session.endTime = start.addingTimeInterval(actual)
        session.plannedDuration = 1500
        session.actualDuration = actual
        session.status = status.rawValue
        session.phase = FocusPhase.focus.rawValue
        session.earnedPoints = 0
        session.roundIndex = 1
        session.createdAt = start
        session.updatedAt = start
        session.tag = tag
        return session
    }
}

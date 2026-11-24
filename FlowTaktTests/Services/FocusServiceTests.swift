import XCTest
import CoreData
@testable import FlowTakt

// MARK: - FocusServiceTests
// 测试 FocusService 核心功能：创建会话、完成/中断/放弃会话、查询今日会话、当前会话

@MainActor
final class FocusServiceTests: XCTestCase {
    var persistence: PersistenceController!
    var notificationService: MockNotificationService!
    var focusService: FocusService!

    override func setUp() {
        super.setUp()
        persistence = PersistenceController(inMemory: true)
        notificationService = MockNotificationService()
        focusService = FocusService(
            persistenceController: persistence,
            notificationService: notificationService
        )
    }

    override func tearDown() {
        focusService = nil
        notificationService = nil
        persistence = nil
        super.tearDown()
    }

    // ========================================================================
    // MARK: - 创建会话
    // ========================================================================

    func testStartFocusSession_GivenValidInput_ThenAllPropertiesAreSetCorrectly() {
        // Given
        let duration: TimeInterval = 25 * 60

        // When
        let session = focusService.startFocusSession(
            task: nil,
            plannedDuration: duration,
            phase: .focus,
            roundIndex: 1
        )

        // Then
        XCTAssertEqual(session.phase, FocusPhase.focus.rawValue)
        XCTAssertEqual(session.plannedDuration, duration)
        XCTAssertEqual(session.status, SessionStatus.running.rawValue)
        XCTAssertEqual(session.earnedPoints, 0)
        XCTAssertEqual(session.roundIndex, 1)
        XCTAssertNotNil(session.id)
        XCTAssertNotNil(session.startTime)
        XCTAssertNotNil(session.createdAt)
        XCTAssertNil(session.task)
    }

    func testStartFocusSession_WithTask_ThenSessionIsProperlyLinked() {
        // Given
        let context = persistence.viewContext
        let task = Task(context: context)
        task.storageId = UUID()
        task.title = "测试任务"
        task.status = TaskStatus.active.rawValue
        task.estimatedPomodoros = 2
        task.completedPomodoros = 0
        task.priority = 2
        task.displayOrder = 0
        task.createdAt = Date()
        task.updatedAt = Date()
        try? context.save()

        // When
        let session = focusService.startFocusSession(
            task: task,
            plannedDuration: 1500,
            phase: .focus,
            roundIndex: 1
        )

        // Then
        XCTAssertNotNil(session.task)
        XCTAssertEqual(session.task?.id, task.id)
        XCTAssertEqual(session.task?.title, "测试任务")
    }

    func testStartFocusSession_WithShortBreakPhase_ThenPhaseIsSetCorrectly() {
        // Given
        let duration: TimeInterval = 5 * 60

        // When
        let session = focusService.startFocusSession(
            task: nil,
            plannedDuration: duration,
            phase: .shortBreak,
            roundIndex: 1
        )

        // Then
        XCTAssertEqual(session.phase, FocusPhase.shortBreak.rawValue)
        XCTAssertEqual(session.plannedDuration, duration)
    }

    func testStartFocusSession_WithLongBreakPhase_ThenPhaseIsSetCorrectly() {
        // Given
        let duration: TimeInterval = 15 * 60

        // When
        let session = focusService.startFocusSession(
            task: nil,
            plannedDuration: duration,
            phase: .longBreak,
            roundIndex: 2
        )

        // Then
        XCTAssertEqual(session.phase, FocusPhase.longBreak.rawValue)
        XCTAssertEqual(session.plannedDuration, duration)
        XCTAssertEqual(session.roundIndex, 2)
    }

    func testStartFocusSession_SchedulesNotification() {
        // Given
        let duration: TimeInterval = 25 * 60

        // When
        let session = focusService.startFocusSession(
            task: nil,
            plannedDuration: duration,
            phase: .focus,
            roundIndex: 1
        )

        // Then
        XCTAssertTrue(notificationService.scheduleSessionEndNotificationCalled)
        XCTAssertEqual(notificationService.lastScheduledSessionId, session.id)
        XCTAssertEqual(notificationService.lastScheduledTimeInterval, duration)
    }

    // ========================================================================
    // MARK: - 完成会话
    // ========================================================================

    func testCompleteSession_GivenRunningSession_ThenStatusBecomesCompleted() {
        // Given
        let session = focusService.startFocusSession(
            task: nil,
            plannedDuration: 1500,
            phase: .focus,
            roundIndex: 1
        )

        // When
        focusService.completeSession(session)

        // Then
        let fetchedSessions = focusService.fetchTodaysSessions()
        let completedSession = fetchedSessions.first!
        XCTAssertEqual(completedSession.status, SessionStatus.completed.rawValue)
        XCTAssertTrue(completedSession.actualDuration > 0)
        XCTAssertNotNil(completedSession.endTime)
        XCTAssertEqual(completedSession.earnedPoints, Int16(AppConstants.pointsPerCompletedPomodoro))
    }

    func testCompleteSession_WithLinkedTask_ThenTaskPomodoroCountIsIncremented() {
        // Given
        let context = persistence.viewContext
        let task = Task(context: context)
        task.storageId = UUID()
        task.title = "测试任务"
        task.completedPomodoros = 0
        task.status = TaskStatus.active.rawValue
        task.estimatedPomodoros = 2
        task.priority = 2
        task.displayOrder = 0
        task.createdAt = Date()
        task.updatedAt = Date()
        try? context.save()

        let session = focusService.startFocusSession(
            task: task,
            plannedDuration: 1500,
            phase: .focus,
            roundIndex: 1
        )

        // When
        focusService.completeSession(session)

        // Then
        XCTAssertEqual(task.completedPomodoros, 1)
    }

    func testCompleteSession_CancelsNotification() {
        // Given
        let session = focusService.startFocusSession(
            task: nil,
            plannedDuration: 1500,
            phase: .focus,
            roundIndex: 1
        )

        // When
        focusService.completeSession(session)

        // Then
        XCTAssertTrue(notificationService.cancelNotificationCalled)
        XCTAssertEqual(notificationService.lastCancelledIdentifier, session.id.uuidString)
    }

    // ========================================================================
    // MARK: - 中断与放弃
    // ========================================================================

    func testInterruptSession_GivenRunningSession_ThenStatusBecomesInterrupted() {
        // Given
        let session = focusService.startFocusSession(
            task: nil,
            plannedDuration: 1500,
            phase: .focus,
            roundIndex: 1
        )

        // When
        focusService.interruptSession(session)

        // Then
        let fetched = focusService.fetchTodaysSessions().first!
        XCTAssertEqual(fetched.status, SessionStatus.interrupted.rawValue)
        XCTAssertNotNil(fetched.endTime)
        XCTAssertTrue(fetched.actualDuration > 0)
    }

    func testAbandonSession_GivenRunningSession_ThenStatusAbandonedAndPointsDeducted() {
        // Given
        let session = focusService.startFocusSession(
            task: nil,
            plannedDuration: 1500,
            phase: .focus,
            roundIndex: 1
        )

        // When
        focusService.abandonSession(session)

        // Then
        let fetched = focusService.fetchTodaysSessions().first!
        XCTAssertEqual(fetched.status, SessionStatus.earlyCompleted.rawValue)
        // 用户反馈 2026-11-17：提前结束保留净时长但不发积分；#17：应记录结束时间
        XCTAssertEqual(fetched.earnedPoints, 0)
        XCTAssertNotNil(fetched.endTime, "放弃会话应记录 endTime，保证数据完整性")
    }

    func testInterruptSession_CancelsNotification() {
        // Given
        let session = focusService.startFocusSession(
            task: nil,
            plannedDuration: 1500,
            phase: .focus,
            roundIndex: 1
        )

        // When
        focusService.interruptSession(session)

        // Then
        XCTAssertTrue(notificationService.cancelNotificationCalled)
        XCTAssertEqual(notificationService.lastCancelledIdentifier, session.id.uuidString)
    }

    func testAbandonSession_CancelsNotification() {
        // Given
        let session = focusService.startFocusSession(
            task: nil,
            plannedDuration: 1500,
            phase: .focus,
            roundIndex: 1
        )

        // When
        focusService.abandonSession(session)

        // Then
        XCTAssertTrue(notificationService.cancelNotificationCalled)
        XCTAssertEqual(notificationService.lastCancelledIdentifier, session.id.uuidString)
    }

    // ========================================================================
    // MARK: - 查询今日会话
    // ========================================================================

    func testFetchTodaysSessions_GivenSessionsCreatedToday_ThenReturnsAllTodaySessions() {
        // Given
        _ = focusService.startFocusSession(task: nil, plannedDuration: 1500, phase: .focus, roundIndex: 1)
        _ = focusService.startFocusSession(task: nil, plannedDuration: 1500, phase: .focus, roundIndex: 2)

        // When
        let todaySessions = focusService.fetchTodaysSessions()

        // Then
        XCTAssertEqual(todaySessions.count, 2)
    }

    func testFetchTodaysSessions_GivenNoSessionsToday_ThenReturnsEmptyArray() {
        // When
        let todaySessions = focusService.fetchTodaysSessions()

        // Then
        XCTAssertTrue(todaySessions.isEmpty)
    }

    // ========================================================================
    // MARK: - 当前会话
    // ========================================================================

    func testGetCurrentSession_GivenRunningSession_ThenReturnsSession() {
        // Given
        let session = focusService.startFocusSession(
            task: nil,
            plannedDuration: 1500,
            phase: .focus,
            roundIndex: 1
        )

        // When
        let current = focusService.getCurrentSession()

        // Then
        XCTAssertNotNil(current)
        XCTAssertEqual(current?.id, session.id)
    }

    func testGetCurrentSession_AfterComplete_ThenReturnsNil() {
        // Given
        let session = focusService.startFocusSession(
            task: nil,
            plannedDuration: 1500,
            phase: .focus,
            roundIndex: 1
        )
        focusService.completeSession(session)

        // When
        let current = focusService.getCurrentSession()

        // Then
        XCTAssertNil(current)
    }

    func testGetCurrentSession_AfterAbandon_ThenReturnsNil() {
        // Given
        let session = focusService.startFocusSession(
            task: nil,
            plannedDuration: 1500,
            phase: .focus,
            roundIndex: 1
        )
        focusService.abandonSession(session)

        // When
        let current = focusService.getCurrentSession()

        // Then
        XCTAssertNil(current)
    }

    // ========================================================================
    // MARK: - 边界条件
    // ========================================================================

    func testStartFocusSession_WithZeroPlannedDuration_ThenSessionStillCreated() {
        // Given
        let session = focusService.startFocusSession(
            task: nil,
            plannedDuration: 0,
            phase: .focus,
            roundIndex: 1
        )

        // Then
        XCTAssertEqual(session.plannedDuration, 0)
        XCTAssertEqual(session.status, SessionStatus.running.rawValue)
    }

    func testCompleteSession_ThenSessionAppearsInTodaysSessions() {
        // Given
        let session = focusService.startFocusSession(
            task: nil,
            plannedDuration: 1500,
            phase: .focus,
            roundIndex: 1
        )
        focusService.completeSession(session)

        // When
        let today = focusService.fetchTodaysSessions()

        // Then
        XCTAssertEqual(today.count, 1)
        XCTAssertEqual(today.first?.status, SessionStatus.completed.rawValue)
    }

    // ========================================================================
    // MARK: - 回归测试：guard let 保护路径
    // ========================================================================

    func testCompleteSession_GivenDeletedSession_ThenDoesNotCrash() {
        // Given
        let session = focusService.startFocusSession(
            task: nil,
            plannedDuration: 1500,
            phase: .focus,
            roundIndex: 1
        )
        let context = persistence.viewContext
        context.delete(session)
        try? context.save()

        // When / Then
        focusService.completeSession(session)
        XCTAssertTrue(true, "对已删除会话调用 completeSession 不应崩溃")
    }

    func testInterruptSession_GivenDeletedSession_ThenDoesNotCrash() {
        // Given
        let session = focusService.startFocusSession(
            task: nil,
            plannedDuration: 1500,
            phase: .focus,
            roundIndex: 1
        )
        let context = persistence.viewContext
        context.delete(session)
        try? context.save()

        // When / Then
        focusService.interruptSession(session)
        XCTAssertTrue(true, "对已删除会话调用 interruptSession 不应崩溃")
    }

    func testAbandonSession_GivenDeletedSession_ThenDoesNotCrash() {
        // Given
        let session = focusService.startFocusSession(
            task: nil,
            plannedDuration: 1500,
            phase: .focus,
            roundIndex: 1
        )
        let context = persistence.viewContext
        context.delete(session)
        try? context.save()

        // When / Then
        focusService.abandonSession(session)
        XCTAssertTrue(true, "对已删除会话调用 abandonSession 不应崩溃")
    }

    // ========================================================================
    // MARK: - 状态机守卫（幂等 / 逆序操作）
    // ========================================================================

    func testCompleteSession_Twice_ThenTaskCountIncrementedOnlyOnce() {
        // Given
        let context = persistence.viewContext
        let task = Task(context: context)
        task.storageId = UUID()
        task.title = "幂等测试任务"
        task.completedPomodoros = 0
        task.status = TaskStatus.active.rawValue
        task.estimatedPomodoros = 2
        task.priority = 2
        task.displayOrder = 0
        task.createdAt = Date()
        task.updatedAt = Date()
        try? context.save()

        let session = focusService.startFocusSession(
            task: task,
            plannedDuration: 1500,
            phase: .focus,
            roundIndex: 1
        )

        // When - 重复 complete
        focusService.completeSession(session)
        focusService.completeSession(session)

        // Then - 任务番茄计数只 +1
        XCTAssertEqual(task.completedPomodoros, 1, "重复 complete 不应重复累加番茄计数")
        let fetched = focusService.fetchTodaysSessions().first!
        XCTAssertEqual(fetched.status, SessionStatus.completed.rawValue)
    }

    func testInterruptSession_AfterComplete_ThenStatusStaysCompleted() {
        // Given
        let session = focusService.startFocusSession(
            task: nil,
            plannedDuration: 1500,
            phase: .focus,
            roundIndex: 1
        )
        focusService.completeSession(session)

        // When - 已完成后再 interrupt（逆序操作）
        focusService.interruptSession(session)

        // Then - 状态不被覆盖为 interrupted
        let fetched = focusService.fetchTodaysSessions().first!
        XCTAssertEqual(fetched.status, SessionStatus.completed.rawValue, "已完成会话不应被 interrupt 覆盖")
        XCTAssertEqual(fetched.earnedPoints, Int16(AppConstants.pointsPerCompletedPomodoro))
    }

    func testCompleteSession_AfterAbandon_ThenStatusStaysAbandoned() {
        // Given
        let session = focusService.startFocusSession(
            task: nil,
            plannedDuration: 1500,
            phase: .focus,
            roundIndex: 1
        )
        focusService.abandonSession(session)

        // When - 已放弃后再 complete（逆序操作）
        focusService.completeSession(session)

        // Then - 状态不被覆盖为 completed
        let fetched = focusService.fetchTodaysSessions().first!
        XCTAssertEqual(fetched.status, SessionStatus.earlyCompleted.rawValue, "提前结束会话不应被 complete 覆盖")
    }

    // ========================================================================
    // MARK: - 防重入（孤儿 running 会话防御）
    // ========================================================================

    func testStartFocusSession_GivenExistingRunningSession_ThenOldSessionInterrupted() {
        // Given
        let first = focusService.startFocusSession(
            task: nil,
            plannedDuration: 1500,
            phase: .focus,
            roundIndex: 1
        )

        // When - 再次创建（异常路径：重复启动）
        let second = focusService.startFocusSession(
            task: nil,
            plannedDuration: 1500,
            phase: .focus,
            roundIndex: 2
        )

        // Then - 旧会话被中断，新会话 running
        let today = focusService.fetchTodaysSessions()
        let firstFetched = today.first { $0.id == first.id }
        XCTAssertEqual(firstFetched?.status, SessionStatus.interrupted.rawValue, "旧 running 会话应被中断，避免孤儿会话")
        let secondFetched = today.first { $0.id == second.id }
        XCTAssertEqual(secondFetched?.status, SessionStatus.running.rawValue)
        XCTAssertEqual(focusService.getCurrentSession()?.id, second.id, "当前会话应为最新创建的会话")
    }

    // ========================================================================
    // MARK: - 中断原因记录（放弃会话时可选）
    // ========================================================================

    func testAbandonSession_WithReason_ThenReasonPersisted() {
        // Given
        let session = focusService.startFocusSession(
            task: nil,
            plannedDuration: 1500,
            phase: .focus,
            roundIndex: 1
        )

        // When - 带原因放弃
        focusService.abandonSession(session, reason: "电话")

        // Then - 原因持久化到会话
        let fetched = focusService.fetchTodaysSessions().first!
        XCTAssertEqual(fetched.status, SessionStatus.earlyCompleted.rawValue)
        XCTAssertEqual(fetched.interruptionReason, "电话", "中断原因应写入会话")
    }

    func testAbandonSession_WithoutReason_ThenReasonIsNil() {
        // Given
        let session = focusService.startFocusSession(
            task: nil,
            plannedDuration: 1500,
            phase: .focus,
            roundIndex: 1
        )

        // When - 经协议扩展重载放弃（不带原因）
        focusService.abandonSession(session)

        // Then
        let fetched = focusService.fetchTodaysSessions().first!
        XCTAssertEqual(fetched.status, SessionStatus.earlyCompleted.rawValue)
        XCTAssertNil(fetched.interruptionReason, "未传原因时应为 nil")
    }

    // ========================================================================
    // MARK: - 审查修复回归测试（2026-08-12）：完成会话查询只统计专注阶段
    // ========================================================================

    func testFetchAllCompletedSessions_GivenFocusAndBreakCompleted_ThenOnlyFocusCounted() {
        // Given：创建 2 个完成会话（1 专注 + 1 短休息）
        let context = persistence.viewContext
        for (i, phase) in [FocusPhase.focus, FocusPhase.shortBreak].enumerated() {
            let session = FocusSession(context: context)
            session.storageId = UUID()
            session.startTime = Date().addingTimeInterval(TimeInterval(-3600 + i * 60))
            session.endTime = Date()
            session.plannedDuration = 1500
            session.actualDuration = 1500
            session.phase = phase.rawValue
            session.roundIndex = Int16(i + 1)
            session.status = SessionStatus.completed.rawValue
            session.earnedPoints = phase == .focus ? 10 : 0
            session.createdAt = Date()
            session.updatedAt = Date()
        }
        try? context.save()

        // When
        let allCompleted = focusService.fetchAllCompletedSessions()

        // Then
        XCTAssertEqual(allCompleted.count, 1, "只应统计专注阶段完成会话")
        XCTAssertEqual(allCompleted.first?.phase, FocusPhase.focus.rawValue)
    }

    func testFetchCompletedSessions_InRange_GivenFocusAndBreakCompleted_ThenOnlyFocusCounted() {
        // Given：创建 1 专注 + 1 短休息完成（今天区间内）
        let context = persistence.viewContext
        for phase in [FocusPhase.focus, FocusPhase.shortBreak] {
            let session = FocusSession(context: context)
            session.storageId = UUID()
            session.startTime = Date()
            session.endTime = Date()
            session.plannedDuration = 1500
            session.actualDuration = 1500
            session.phase = phase.rawValue
            session.roundIndex = 1
            session.status = SessionStatus.completed.rawValue
            session.earnedPoints = phase == .focus ? 10 : 0
            session.createdAt = Date()
            session.updatedAt = Date()
        }
        try? context.save()

        // When
        let inRange = focusService.fetchCompletedSessions(from: Date().startOfDay, to: Date().endOfDay)

        // Then
        XCTAssertEqual(inRange.count, 1, "区间查询只应统计专注阶段完成会话")
        XCTAssertEqual(inRange.first?.phase, FocusPhase.focus.rawValue)
    }

    // ========================================================================
    // MARK: - 提前结束保留时长（用户反馈 2026-11-17）
    // ========================================================================

    func testAbandonSession_GivenRunningSession_ThenDurationPreservedAndEarlyCompleted() {
        // Given - 会话已开始，模拟已专注 5 分钟（updatedAt 回拨 300 秒）
        let session = focusService.startFocusSession(
            task: nil, plannedDuration: 1500, phase: .focus, roundIndex: 1)
        session.updatedAt = Date().addingTimeInterval(-300)
        try? persistence.viewContext.save()

        // When - 用户提前结束
        focusService.abandonSession(session)

        // Then - 净专注时长保留，状态为提前完成，不发积分、不增加番茄
        let fetched = focusService.fetchTodaysSessions().first!
        XCTAssertEqual(fetched.status, SessionStatus.earlyCompleted.rawValue)
        XCTAssertGreaterThanOrEqual(fetched.actualDuration, 299, "提前结束必须保留净专注秒数")
        XCTAssertEqual(fetched.earnedPoints, 0, "提前结束不发积分")
        XCTAssertTrue(fetched.countsTowardDuration, "提前结束应计入时长统计")
        XCTAssertFalse(fetched.isCompleted, "提前结束不算完成番茄")
        XCTAssertTrue(focusService.fetchAllCompletedSessions().isEmpty, "提前结束不得进入完成番茄口径")
        XCTAssertEqual(focusService.fetchAllSessionsForDuration().count, 1, "提前结束应进入时长口径")
    }

    func testAbandonSession_WhenPaused_ThenOnlyNetActiveTimePreserved() {
        // Given - 运行 200 秒后暂停（落库 200 秒），再挂起 100 秒
        let session = focusService.startFocusSession(
            task: nil, plannedDuration: 1500, phase: .focus, roundIndex: 1)
        session.updatedAt = Date().addingTimeInterval(-200)
        focusService.pauseSession(session, activeSeconds: 200)
        session.updatedAt = Date().addingTimeInterval(-100)  // 暂停期间挂钟多走 100 秒

        // When
        focusService.abandonSession(session)

        // Then - 暂停段不计入，仅保留 200 秒净专注
        XCTAssertEqual(session.actualDuration, 200, accuracy: 1.0)
        XCTAssertEqual(session.status, SessionStatus.earlyCompleted.rawValue)
    }

    // ========================================================================
    // MARK: - 系统替换路径保留净时长（用户反馈 2026-11-19 修订）
    // ========================================================================

    /// 暂停中的孤儿会话已有真实净专注 → 被新会话替换时必须保留该时长。
    ///
    /// 历史：2026-11-17 曾判为 discard（不计时长），用户反馈「暂停后时长被清空」，
    /// 2026-11-19 改为「净时长 ≥ 1 秒即按 earlyCompleted 结算」。
    func testStartFocusSession_GivenPausedOrphanWithTime_ThenKeepsNetDuration() {
        // Given - 一个暂停中的会话（已落库 120 秒净专注）
        let orphan = focusService.startFocusSession(
            task: nil, plannedDuration: 1500, phase: .focus, roundIndex: 1)
        focusService.pauseSession(orphan, activeSeconds: 120)

        // When - 新会话启动（如 Siri/快捷指令、从其它入口再开一次计时）
        _ = focusService.startFocusSession(
            task: nil, plannedDuration: 1500, phase: .focus, roundIndex: 1)

        // Then - 孤儿结算为 earlyCompleted：净时长保留并计入时长口径，但不算完成番茄
        let fetched = focusService.fetchTodaysSessions().first { $0.id == orphan.id }!
        XCTAssertEqual(fetched.status, SessionStatus.earlyCompleted.rawValue,
                       "有净时长的暂停会话被替换时应保留时长")
        XCTAssertEqual(fetched.interruptionReason, "replaced_by_new_session")
        XCTAssertEqual(fetched.actualDuration, 120, accuracy: 1.0)
        XCTAssertTrue(fetched.countsTowardDuration, "已专注的净时长必须计入统计")
        XCTAssertFalse(fetched.isCompleted, "被替换的会话不算完成番茄")
        XCTAssertTrue(focusService.fetchAllSessionsForDuration().contains { $0.id == orphan.id })
    }

    /// 跨进程残留的 running 孤儿（净时长按挂钟已远超计划）→ 必须封顶到计划时长。
    ///
    /// 2026-11-19 审查补：改判 earlyCompleted（计入统计）后，若不做封顶，
    /// 「三天前开始、忘了停」的残留会话会被写成 4320 分钟专注，直接污染统计与标签分布。
    func testStartFocusSession_GivenOverdueRunningOrphan_ThenDurationCappedToPlanned() {
        // Given - 会话停在 running，开始时间被回拨 3 天（模拟进程被回收）
        let orphan = focusService.startFocusSession(
            task: nil, plannedDuration: 1500, phase: .focus, roundIndex: 1)
        orphan.startTime = Date().addingTimeInterval(-3 * 24 * 3600)
        orphan.updatedAt = Date().addingTimeInterval(-3 * 24 * 3600)

        // When
        _ = focusService.startFocusSession(
            task: nil, plannedDuration: 1500, phase: .focus, roundIndex: 1)

        // Then - 净时长以计划时长封顶，状态为 earlyCompleted（时长计入、不算完成番茄）
        XCTAssertEqual(orphan.actualDuration, 1500, accuracy: 1.0,
                       "超时残留会话的净时长必须封顶到计划时长")
        XCTAssertEqual(orphan.status, SessionStatus.earlyCompleted.rawValue)
        XCTAssertTrue(orphan.countsTowardDuration)
    }

    /// 刚开始（净时长 < 1 秒）就暂停的孤儿 → 不制造空会话
    func testStartFocusSession_GivenZeroTimeOrphan_ThenDiscarded() {        // Given - 创建后立即暂停（净时长为 0）
        let orphan = focusService.startFocusSession(
            task: nil, plannedDuration: 1500, phase: .focus, roundIndex: 1)
        focusService.pauseSession(orphan, activeSeconds: 0)

        // When
        _ = focusService.startFocusSession(
            task: nil, plannedDuration: 1500, phase: .focus, roundIndex: 1)

        // Then - abandoned，不进入时长口径
        let fetched = focusService.fetchTodaysSessions().first { $0.id == orphan.id }!
        XCTAssertEqual(fetched.status, SessionStatus.abandoned.rawValue)
        XCTAssertFalse(fetched.countsTowardDuration)
    }

    func testDiscardSession_ThenDurationNotCountedButReasonKept() {
        // Given - 运行中的会话
        let session = focusService.startFocusSession(
            task: nil, plannedDuration: 1500, phase: .focus, roundIndex: 1)

        // When - 系统原因丢弃
        focusService.discardSession(session, reason: "app_reset")

        // Then - abandoned、原因保留、不计时长
        let fetched = focusService.fetchTodaysSessions().first!
        XCTAssertEqual(fetched.status, SessionStatus.abandoned.rawValue)
        XCTAssertEqual(fetched.interruptionReason, "app_reset")
        XCTAssertFalse(fetched.countsTowardDuration)
        XCTAssertTrue(focusService.fetchAllSessionsForDuration().isEmpty)
    }
}

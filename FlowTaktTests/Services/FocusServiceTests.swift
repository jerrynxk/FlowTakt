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
        task.id = UUID()
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
        task.id = UUID()
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
        XCTAssertEqual(fetched.status, SessionStatus.abandoned.rawValue)
        // 审查 #16：放弃不再写无效惩罚积分（统计口径只算 completed）；#17：应记录结束时间
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
        task.id = UUID()
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
        XCTAssertEqual(fetched.status, SessionStatus.abandoned.rawValue, "已放弃会话不应被 complete 覆盖")
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
        XCTAssertEqual(fetched.status, SessionStatus.abandoned.rawValue)
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
        XCTAssertEqual(fetched.status, SessionStatus.abandoned.rawValue)
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
            session.id = UUID()
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
            session.id = UUID()
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
}

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
        XCTAssertEqual(fetched.earnedPoints, Int16(AppConstants.pointsPenaltyPerInterrupt))
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
    // MARK: - AchievementService 注入
    // ========================================================================

    func testSetAchievementService_DoesNotCrash() {
        // Given
        let mockAchService = MockAchievementService()

        // When / Then
        focusService.achievementService = mockAchService
        XCTAssertNotNil(focusService.achievementService, "AchievementService 应被正确注入")
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
}

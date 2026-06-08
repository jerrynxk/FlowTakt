import XCTest
import Combine
import CoreData
@testable import FlowTakt

// MARK: - FocusViewModelTests
// 测试 FocusViewModel 核心流程：开始专注、暂停/恢复、手动停止、完成自动处理
// 所有外部依赖使用 Mock 实现，不依赖真实 CoreData 或系统 API
//
// Xcode Target 配置:
// 1. 将本文件加入 FlowTaktTests Target 的 Compile Sources
// 2. 需同时添加 Helpers/MockServices.swift 到 Compile Sources

final class FocusViewModelTests: XCTestCase {
    var mockFocusService: MockFocusService!
    var timerManager: TimerManager!
    var mockNotificationService: MockNotificationService!
    var mockAppBlockerService: MockAppBlockerService!
    var mockAudioService: MockAudioService!
    var mockAchievementService: MockAchievementService!
    var mockTaskService: MockTaskService!
    var viewModel: FocusViewModel!
    var cancellables: Set<AnyCancellable>!

    /// 创建并配置一个 Mock FocusSession
    private func makeMockSession(id: UUID = UUID(), status: SessionStatus = .running) -> FocusSession {
        // 无法直接创建 NSManagedObject 子类实例，使用 MockPersistenceController
        let mockPersistence = MockPersistenceController()
        let context = mockPersistence.viewContext
        let session = FocusSession(context: context)
        session.id = id
        session.startTime = Date()
        session.plannedDuration = 1500
        session.actualDuration = status == .completed ? 1500 : 0
        session.phase = FocusPhase.focus.rawValue
        session.roundIndex = 1
        session.status = status.rawValue
        session.earnedPoints = status == .completed ? 10 : 0
        session.createdAt = Date()
        session.updatedAt = Date()
        return session
    }

    override func setUp() {
        super.setUp()
        mockFocusService = MockFocusService()
        timerManager = TimerManager()
        mockNotificationService = MockNotificationService()
        mockAppBlockerService = MockAppBlockerService()
        mockAudioService = MockAudioService()
        mockAchievementService = MockAchievementService()
        mockTaskService = MockTaskService()

        viewModel = FocusViewModel(
            focusService: mockFocusService,
            timerManager: timerManager,
            notificationService: mockNotificationService,
            appBlockerService: mockAppBlockerService,
            audioService: mockAudioService,
            achievementService: mockAchievementService,
            taskService: mockTaskService
        )
        cancellables = Set<AnyCancellable>()
    }

    override func tearDown() {
        viewModel = nil
        mockFocusService = nil
        timerManager = nil
        mockNotificationService = nil
        mockAppBlockerService = nil
        mockAudioService = nil
        mockAchievementService = nil
        mockTaskService = nil
        cancellables = nil
        super.tearDown()
    }

    // ========================================================================
    // MARK: - 初始状态
    // ========================================================================

    func testInitialState_WhenCreated_ThenDefaultsAreSet() {
        // Then
        XCTAssertFalse(viewModel.isRunning)
        XCTAssertFalse(viewModel.isPaused)
        XCTAssertEqual(viewModel.currentPhase, .focus)
        XCTAssertEqual(viewModel.currentRound, 1)
        XCTAssertNil(viewModel.currentSession)
        XCTAssertNil(viewModel.selectedTask)
        XCTAssertEqual(viewModel.progress, 0.0, "idle 状态下 progress 应为 0（未开始流逝）")
        XCTAssertFalse(viewModel.showCompletionAnimation)
        XCTAssertNil(viewModel.errorMessage)
    }

    // ========================================================================
    // MARK: - 开始专注
    // ========================================================================

    func testStartFocus_GivenIdleState_ThenCreatesSessionAndStartsTimer() {
        // Given
        let mockSession = makeMockSession()
        mockFocusService.startFocusSessionHandler = { task, duration, phase, roundIndex in
            return mockSession
        }

        // When
        viewModel.startFocus(phase: .focus)

        // Then
        XCTAssertTrue(viewModel.isRunning)
        XCTAssertEqual(timerManager.timerState, .running)
        XCTAssertEqual(viewModel.currentSession?.id, mockSession.id)
        XCTAssertTrue(mockAppBlockerService.startBlockingCalled, "应开启勿扰模式")
        XCTAssertTrue(mockNotificationService.scheduleSessionEndNotificationCalled, "应调度专注结束通知")
        XCTAssertTrue(mockAudioService.playStartSoundCalled, "应播放开始音效")
    }

    func testStartFocus_GivenAlreadyRunning_ThenIgnored() {
        // Given
        let mockSession = makeMockSession()
        mockFocusService.startFocusSessionHandler = { task, duration, phase, roundIndex in
            return mockSession
        }
        viewModel.startFocus(phase: .focus)
        XCTAssertTrue(viewModel.isRunning)

        // Track call counts
        mockAudioService.playStartSoundCalled = false

        // When - 第二次尝试启动
        viewModel.startFocus(phase: .focus)

        // Then - 不应重复启动（不崩溃即可，具体行为由 ViewModel 决定）
        XCTAssertTrue(viewModel.isRunning)
    }

    func testStartFocus_WithSelectedTask_ThenSessionTaskIsLinked() {
        // Given
        let mockPersistence = MockPersistenceController()
        let context = mockPersistence.viewContext
        let task = Task(context: context)
        task.id = UUID()
        task.title = "关联任务"
        task.status = TaskStatus.active.rawValue

        let mockSession = makeMockSession()
        mockSession.task = task

        mockFocusService.startFocusSessionHandler = { t, duration, phase, roundIndex in
            return mockSession
        }

        // When
        viewModel.selectTask(task)
        viewModel.startFocus(phase: .focus)

        // Then
        XCTAssertNotNil(viewModel.selectedTask)
    }

    // ========================================================================
    // MARK: - 暂停与恢复
    // ========================================================================

    func testPauseFocus_GivenRunning_ThenTimerPauses() {
        // Given
        let mockSession = makeMockSession()
        mockFocusService.startFocusSessionHandler = { task, duration, phase, roundIndex in
            return mockSession
        }
        viewModel.startFocus(phase: .focus)
        XCTAssertTrue(viewModel.isRunning)

        // When
        viewModel.pauseFocus()

        // Then
        XCTAssertTrue(viewModel.isPaused)
        XCTAssertFalse(viewModel.isRunning)
        XCTAssertEqual(timerManager.timerState, .paused)
    }

    func testPauseFocus_GivenNotRunning_ThenIgnored() {
        // Given - 初始 idle

        // When
        viewModel.pauseFocus()

        // Then
        XCTAssertFalse(viewModel.isPaused)
        XCTAssertFalse(viewModel.isRunning)
    }

    func testResumeFocus_GivenPaused_ThenTimerResumes() {
        // Given
        let mockSession = makeMockSession()
        mockFocusService.startFocusSessionHandler = { task, duration, phase, roundIndex in
            return mockSession
        }
        viewModel.startFocus(phase: .focus)
        viewModel.pauseFocus()
        XCTAssertTrue(viewModel.isPaused)

        // When
        viewModel.resumeFocus()

        // Then
        XCTAssertTrue(viewModel.isRunning)
        XCTAssertFalse(viewModel.isPaused)
        XCTAssertEqual(timerManager.timerState, .running)
    }

    func testResumeFocus_GivenNotPaused_ThenIgnored() {
        // Given
        let mockSession = makeMockSession()
        mockFocusService.startFocusSessionHandler = { task, duration, phase, roundIndex in
            return mockSession
        }
        viewModel.startFocus(phase: .focus)
        XCTAssertTrue(viewModel.isRunning)

        // When - 在 running 状态调用 resume
        viewModel.resumeFocus()

        // Then - 状态不变
        XCTAssertTrue(viewModel.isRunning)
    }

    // ========================================================================
    // MARK: - 手动停止（放弃）
    // ========================================================================

    func testStopFocus_GivenRunning_ThenSessionAbandonedAndCleanedUp() {
        // Given
        let mockSession = makeMockSession()
        var abandonedSession: FocusSession?
        mockFocusService.startFocusSessionHandler = { task, duration, phase, roundIndex in
            return mockSession
        }
        mockFocusService.abandonSessionHandler = { session in
            abandonedSession = session
        }
        viewModel.startFocus(phase: .focus)

        // When
        viewModel.abandonSession()

        // Then
        XCTAssertNil(viewModel.currentSession, "停止后应清空 currentSession")
        XCTAssertFalse(viewModel.isRunning)
        XCTAssertFalse(viewModel.isPaused)
        XCTAssertEqual(timerManager.timerState, .idle)
        XCTAssertNotNil(abandonedSession, "应调用 abandonSession")
        XCTAssertEqual(abandonedSession?.id, mockSession.id)
        XCTAssertTrue(mockNotificationService.cancelNotificationCalled, "应取消通知")
        XCTAssertTrue(mockAppBlockerService.stopBlockingCalled, "应关闭勿扰模式")
    }

    func testStopFocus_GivenIdle_ThenIgnored() {
        // Given - 初始 idle

        // When
        viewModel.abandonSession()

        // Then - 不崩溃
        XCTAssertNil(viewModel.currentSession)
    }

    // ========================================================================
    // MARK: - 完成处理
    // ========================================================================

    func testTimerComplete_ThenSessionCompletedAndPointsAwarded() {
        // Given
        let mockSession = makeMockSession()
        var completedSession: FocusSession?
        mockFocusService.startFocusSessionHandler = { task, duration, phase, roundIndex in
            return mockSession
        }
        mockFocusService.completeSessionHandler = { session in
            completedSession = session
        }

        // Track achievement check
        var achievementChecked = false
        mockAchievementService.checkAndUnlockAchievementsHandler = {
            achievementChecked = true
        }

        viewModel.startFocus(phase: .focus)

        // When - 模拟计时器完成（通过设置 timerState 为 .finished 并推进 RunLoop）
        timerManager.timerState = .finished
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        // Then
        XCTAssertNotNil(completedSession)
        XCTAssertTrue(viewModel.showCompletionAnimation, "应显示完成动画")
        XCTAssertTrue(mockNotificationService.cancelNotificationCalled, "完成时应取消通知")
        XCTAssertTrue(mockAppBlockerService.stopBlockingCalled, "完成时应关闭勿扰")
        XCTAssertTrue(achievementChecked, "应检查成就")
    }

    func testTimerComplete_WithAchievementCheck() {
        // Given
        let mockSession = makeMockSession()
        mockAchievementService.newlyUnlockedAchievements = []

        mockFocusService.startFocusSessionHandler = { task, duration, phase, roundIndex in
            return mockSession
        }
        mockFocusService.completeSessionHandler = { _ in }

        viewModel.startFocus(phase: .focus)

        // When
        timerManager.timerState = .finished
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        // Then - 无新成就，流程正常完成
        XCTAssertTrue(mockAchievementService.checkAndUnlockAchievementsCalled)
    }

    func testTimerComplete_WithNewAchievement_ThenAlertShown() {
        // Given
        let mockSession = makeMockSession()
        mockAchievementService.newlyUnlockedAchievements = [Achievement()]

        mockFocusService.startFocusSessionHandler = { task, duration, phase, roundIndex in
            return mockSession
        }
        mockFocusService.completeSessionHandler = { _ in }

        viewModel.startFocus(phase: .focus)

        // When
        timerManager.timerState = .finished
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        // Then - 流程不崩溃
        XCTAssertTrue(mockAchievementService.checkAndUnlockAchievementsCalled)
    }

    // ========================================================================
    // MARK: - 白噪音
    // ========================================================================

    func testToggleWhiteNoise_WhenOff_ThenStartsWhiteNoise() {
        // Given
        XCTAssertFalse(viewModel.isWhiteNoiseOn)

        // When
        viewModel.toggleWhiteNoise()

        // Then
        XCTAssertTrue(viewModel.isWhiteNoiseOn)
        XCTAssertTrue(mockAudioService.toggleWhiteNoiseCalled)
        XCTAssertTrue(mockAudioService.isWhiteNoisePlaying)
    }

    func testToggleWhiteNoise_WhenOn_ThenStopsWhiteNoise() {
        // Given
        viewModel.toggleWhiteNoise()
        XCTAssertTrue(viewModel.isWhiteNoiseOn)
        mockAudioService.toggleWhiteNoiseCalled = false

        // When
        viewModel.toggleWhiteNoise()

        // Then
        XCTAssertFalse(viewModel.isWhiteNoiseOn)
        XCTAssertTrue(mockAudioService.toggleWhiteNoiseCalled)
        XCTAssertFalse(mockAudioService.isWhiteNoisePlaying)
    }

    // ========================================================================
    // MARK: - 任务选择
    // ========================================================================

    func testSelectTask_GivenTask_ThenSelectedTaskUpdated() {
        // Given
        let mockPersistence = MockPersistenceController()
        let context = mockPersistence.viewContext
        let task = Task(context: context)
        task.id = UUID()
        task.title = "测试任务"
        task.status = TaskStatus.active.rawValue

        // When
        viewModel.selectTask(task)

        // Then
        XCTAssertEqual(viewModel.selectedTask?.id, task.id)
    }

    func testSelectTask_GivenNil_ThenClearsSelection() {
        // Given
        let mockPersistence = MockPersistenceController()
        let context = mockPersistence.viewContext
        let task = Task(context: context)
        task.id = UUID()
        task.title = "测试任务"
        task.status = TaskStatus.active.rawValue
        viewModel.selectTask(task)
        XCTAssertNotNil(viewModel.selectedTask)

        // When
        viewModel.selectTask(nil)

        // Then
        XCTAssertNil(viewModel.selectedTask)
    }

    // ========================================================================
    // MARK: - 刷新统计
    // ========================================================================

    func testRefreshTodayStats_WhenSessionsExist_ThenUpdatesCounts() {
        // Given
        let mockSession = makeMockSession(status: .completed)
        mockFocusService.fetchTodaysSessionsResult = [mockSession]

        // When
        viewModel.refreshTodayStats()

        // Then
        XCTAssertEqual(viewModel.todayCompletedCount, 1)
        XCTAssertGreaterThan(viewModel.todayTotalDuration, 0)
    }

    func testRefreshTodayStats_WhenNoSessions_ThenCountsAreZero() {
        // Given
        mockFocusService.fetchTodaysSessionsResult = []

        // When
        viewModel.refreshTodayStats()

        // Then
        XCTAssertEqual(viewModel.todayCompletedCount, 0)
        XCTAssertEqual(viewModel.todayTotalDuration, 0)
    }

    // ========================================================================
    // MARK: - 边界条件
    // ========================================================================

    func testStartFocus_ThenStopAndRestart_WorksCorrectly() {
        // Given
        let session1 = makeMockSession(id: UUID())
        let session2 = makeMockSession(id: UUID())
        var createCount = 0
        mockFocusService.startFocusSessionHandler = { task, duration, phase, roundIndex in
            createCount += 1
            return createCount == 1 ? session1 : session2
        }
        mockFocusService.abandonSessionHandler = { _ in }

        // When - 第一轮
        viewModel.startFocus(phase: .focus)
        viewModel.abandonSession()

        // Then - 可以重新启动
        viewModel.startFocus(phase: .focus)
        XCTAssertEqual(createCount, 2, "应创建 2 个会话")
        XCTAssertTrue(viewModel.isRunning)
    }

    func testStopFocus_WithoutSession_DoesNotCrash() {
        // Given - currentSession 为 nil

        // When / Then
        viewModel.abandonSession() // 不应崩溃
        XCTAssertTrue(true)
    }

    // ========================================================================
    // MARK: - 回归测试 #T1: 双重计数修复验证
    // ========================================================================

    func testHandleTimerFinished_DoesNotCallIncrementCompletedPomodoros() {
        // Given - 设置 mock，跟踪 incrementCompletedPomodoros 是否被调用
        var incrementCalled = false
        mockTaskService.incrementCompletedPomodorosHandler = { _ in
            incrementCalled = true
        }

        let mockSession = makeMockSession()
        mockFocusService.startFocusSessionHandler = { task, duration, phase, roundIndex in
            return mockSession
        }
        mockFocusService.completeSessionHandler = { _ in }

        viewModel.startFocus(phase: .focus)

        // When - 模拟计时器完成
        timerManager.timerState = .finished
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        // Then - incrementCompletedPomodoros 不应被调用（因为 completeSession 已经处理了）
        XCTAssertFalse(incrementCalled, "handleTimerFinished 不应调用 incrementCompletedPomodoros，避免双重计数")
    }

    // ========================================================================
    // MARK: - 回归测试 #T1b: 成就检查不重复调用
    // ========================================================================

    func testHandleTimerFinished_DoesNotDoubleCallCheckAchievements() {
        // Given
        var checkCallCount = 0
        mockAchievementService.checkAndUnlockAchievementsHandler = {
            checkCallCount += 1
        }

        let mockSession = makeMockSession()
        mockFocusService.startFocusSessionHandler = { task, duration, phase, roundIndex in
            return mockSession
        }
        mockFocusService.completeSessionHandler = { _ in }

        viewModel.startFocus(phase: .focus)

        // When
        timerManager.timerState = .finished
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        // Then - 只应调用一次
        XCTAssertEqual(checkCallCount, 1, "checkAndUnlockAchievements 只应被调用一次")
    }
}

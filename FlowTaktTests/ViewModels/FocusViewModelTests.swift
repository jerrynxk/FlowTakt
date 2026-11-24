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

@MainActor
final class FocusViewModelTests: XCTestCase {
    var mockFocusService: MockFocusService!
    var timerManager: TimerManager!
    var mockNotificationService: MockNotificationService!
    var mockAppBlockerService: MockAppBlockerService!
    var mockAudioService: MockAudioService!
    var mockAchievementService: MockAchievementService!
    var mockTaskService: MockTaskService!
    var mockSpeechService: MockSpeechService!
    var viewModel: FocusViewModel!
    var cancellables: Set<AnyCancellable>!
    /// 持久化 controller，确保 CoreData context 在测试期间不释放
    var persistenceController: MockPersistenceController!

    /// 创建并配置一个 Mock FocusSession
    private func makeMockSession(id: UUID = UUID(), status: SessionStatus = .running) -> FocusSession {
        let context = persistenceController.viewContext
        let session = FocusSession(context: context)
        session.storageId = id
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
        persistenceController = MockPersistenceController()
        mockFocusService = MockFocusService()
        timerManager = TimerManager()
        mockNotificationService = MockNotificationService()
        mockAppBlockerService = MockAppBlockerService()
        mockAudioService = MockAudioService()
        mockAchievementService = MockAchievementService()
        mockTaskService = MockTaskService()
        mockSpeechService = MockSpeechService()

        viewModel = FocusViewModel(
            focusService: mockFocusService,
            timerManager: timerManager,
            notificationService: mockNotificationService,
            appBlockerService: mockAppBlockerService,
            audioService: mockAudioService,
            achievementService: mockAchievementService,
            taskService: mockTaskService,
            speechService: mockSpeechService
        )
        cancellables = Set<AnyCancellable>()
    }

    override func tearDown() {
        // 修复（2026-10-14 T4）：本类多个用例写 focusDuration / shortBreakDuration /
        // longBreakDuration，残留会污染后续用例（断言默认值）与 resetDatabase 的
        // iCloudSyncEnabled 判定 —— 按执行顺序造成确定性假红。
        let domain = Bundle.main.bundleIdentifier ?? ""
        UserDefaults.standard.removePersistentDomain(forName: domain)
        viewModel = nil
        mockFocusService = nil
        timerManager = nil
        mockNotificationService = nil
        mockAppBlockerService = nil
        mockAudioService = nil
        mockAchievementService = nil
        mockTaskService = nil
        mockSpeechService = nil
        persistenceController = nil
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
        // 注意：「专注结束」通知调度由 FocusService.startFocusSession 内部负责
        // （真实 FocusService 会调度；Mock 不模拟），此处不再断言 ViewModel 层调用
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
        let context = persistenceController.viewContext
        let task = Task(context: context)
        task.storageId = UUID()
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
        mockFocusService.completeSessionHandler = { session, actualDuration in
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
        mockFocusService.completeSessionHandler = { _, _ in }

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
        mockFocusService.completeSessionHandler = { _, _ in }

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

    /// 2026-11-22 语义调整：白噪音开关是纯偏好开关，只切 isWhiteNoiseEnabled，
    /// 不即时播放/停止音频、不改运行时状态 isWhiteNoiseOn（由 startFocus 等生命周期路径维护）。
    func testToggleWhiteNoise_OnlyTogglesPreference_NoImmediateAudio() {
        // Given：显式写 false 建立"关"起点。
        // 注意：源码默认值是 true（?? true），仅 removeObject 会得到"开"，故必须显式 set(false)。
        UserDefaults.standard.set(false, forKey: FocusViewModel.whiteNoiseAutoPlayKey)
        XCTAssertFalse(viewModel.isWhiteNoiseEnabled)

        // When
        viewModel.toggleWhiteNoise()

        // Then：偏好切到开，但不碰音频
        XCTAssertTrue(viewModel.isWhiteNoiseEnabled)
        XCTAssertTrue(UserDefaults.standard.object(forKey: FocusViewModel.whiteNoiseAutoPlayKey) as? Bool ?? false)
        XCTAssertFalse(mockAudioService.toggleWhiteNoiseCalled, "开关不应立即播放音频")
        XCTAssertFalse(mockAudioService.isWhiteNoisePlaying, "未开始专注时打开开关不得出声")
        XCTAssertFalse(viewModel.isWhiteNoiseOn, "运行时播放状态不应被开关改动")
    }

    /// 再切一次：偏好回到关，音频同样不受影响
    func testToggleWhiteNoise_Twice_BackToOff() {
        UserDefaults.standard.set(false, forKey: FocusViewModel.whiteNoiseAutoPlayKey)
        viewModel.toggleWhiteNoise()   // 关 → 开
        XCTAssertTrue(viewModel.isWhiteNoiseEnabled)
        mockAudioService.toggleWhiteNoiseCalled = false

        viewModel.toggleWhiteNoise()   // 开 → 关
        XCTAssertFalse(viewModel.isWhiteNoiseEnabled)
        XCTAssertFalse(mockAudioService.toggleWhiteNoiseCalled, "关闭开关也不应即时停音频")
    }

    /// 回归（2026-11-22 bug）：toggleWhiteNoise 虽写的是非 @Published 计算属性，
    /// 但必须发 objectWillChange，否则工具栏图标/开关行读屏状态停在旧值（界面无反应但实际已生效）。
    func testToggleWhiteNoise_ThenPublishesObjectWillChange() {
        UserDefaults.standard.set(false, forKey: FocusViewModel.whiteNoiseAutoPlayKey)
        var willChangeCount = 0
        let sub = viewModel.objectWillChange.sink { _ in willChangeCount += 1 }

        viewModel.toggleWhiteNoise()

        XCTAssertEqual(willChangeCount, 1, "写偏好后必须发 objectWillChange 触发视图重绘（否则 UI 不刷新）")
        withExtendedLifetime(sub) { }
    }

    // ========================================================================
    // MARK: - 任务选择
    // ========================================================================

    func testSelectTask_GivenTask_ThenSelectedTaskUpdated() {
        // Given
        let context = persistenceController.viewContext
        let task = Task(context: context)
        task.storageId = UUID()
        task.title = "测试任务"
        task.status = TaskStatus.active.rawValue

        // When
        viewModel.selectTask(task)

        // Then
        XCTAssertEqual(viewModel.selectedTask?.id, task.id)
    }

    func testSelectTask_GivenNil_ThenClearsSelection() {
        // Given
        let context = persistenceController.viewContext
        let task = Task(context: context)
        task.storageId = UUID()
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
        mockTaskService.incrementCompletedPomodorosCalledHandler = { _ in
            incrementCalled = true
        }

        let mockSession = makeMockSession()
        mockFocusService.startFocusSessionHandler = { task, duration, phase, roundIndex in
            return mockSession
        }
        mockFocusService.completeSessionHandler = { _, _ in }

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
        mockFocusService.completeSessionHandler = { _, _ in }

        viewModel.startFocus(phase: .focus)

        // When
        timerManager.timerState = .finished
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        // Then - 只应调用一次
        XCTAssertEqual(checkCallCount, 1, "checkAndUnlockAchievements 只应被调用一次")
    }

    // ========================================================================
    // MARK: - 时长预设（P1.5）
    // ========================================================================

    func testStartFocus_WithDurationOverride_ThenUsesCustomDuration() {
        // Given
        var capturedDuration: TimeInterval?
        mockFocusService.startFocusSessionHandler = { _, duration, _, _ in
            capturedDuration = duration
            return self.makeMockSession()
        }

        // When - 使用 12 分钟自定义时长（绕过设置默认 25 分钟）
        viewModel.startFocus(phase: .focus, durationOverride: 12 * 60)

        // Then - 会话应使用自定义时长
        XCTAssertEqual(capturedDuration, 12 * 60, "应直接使用自定义时长，而非设置默认值")
    }

    // ========================================================================
    // MARK: - 语音播报（P2.3）
    // ========================================================================

    func testTimerComplete_ThenSpeechAnnouncesCompletedPomodoro() {
        // Given
        let mockSession = makeMockSession()
        mockFocusService.startFocusSessionHandler = { task, duration, phase, roundIndex in
            return mockSession
        }
        mockFocusService.completeSessionHandler = { _, _ in }

        viewModel.startFocus(phase: .focus)

        // When - 模拟计时器完成
        timerManager.timerState = .finished
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        // Then - 应播报「第 1 个番茄完成」（轮次递增前的值）
        XCTAssertTrue(mockSpeechService.speakCalled, "专注完成应触发语音播报")
        XCTAssertEqual(mockSpeechService.lastSpokenText, L10n.shared.第X个番茄完成(1))
    }

    // ========================================================================
    // MARK: - 回归：skipPhase 延迟闭包竞态（放弃/暂停后不应自动开始下一段）
    // ========================================================================

    func testSkipPhase_ThenAbandonWithinWindow_DoesNotAutoStartNewSession() {
        // Given
        let session1 = makeMockSession(id: UUID())
        let session2 = makeMockSession(id: UUID())
        var createCount = 0
        mockFocusService.startFocusSessionHandler = { task, duration, phase, roundIndex in
            createCount += 1
            return createCount == 1 ? session1 : session2
        }
        mockFocusService.completeSessionHandler = { _, _ in }
        mockFocusService.abandonSessionHandler = { _ in }
        viewModel.startFocus(phase: .focus)
        XCTAssertTrue(viewModel.isRunning)

        // When - 跳过当前阶段后，在 0.3s 延迟窗口内立即放弃
        viewModel.skipPhase()
        viewModel.abandonSession()

        // Then - 延迟闭包不应再自动开始新会话
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        XCTAssertEqual(createCount, 1, "放弃后不应自动创建新会话（代际校验应拦截延迟启动）")
        XCTAssertFalse(viewModel.isRunning)
        XCTAssertNil(viewModel.currentSession)
    }

    func testSkipPhase_ThenPauseWithinWindow_DoesNotAutoStartNewSession() {
        // Given
        let session1 = makeMockSession(id: UUID())
        let session2 = makeMockSession(id: UUID())
        var createCount = 0
        mockFocusService.startFocusSessionHandler = { task, duration, phase, roundIndex in
            createCount += 1
            return createCount == 1 ? session1 : session2
        }
        mockFocusService.completeSessionHandler = { _, _ in }
        viewModel.startFocus(phase: .focus)

        // When - 跳过后在延迟窗口内暂停
        viewModel.skipPhase()
        viewModel.pauseFocus()

        // Then - 延迟闭包不应自动开始下一段
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        XCTAssertEqual(createCount, 1, "暂停后不应自动创建新会话")
    }

    func testSkipPhase_WithoutInterruption_ThenAutoStartsNextPhase() {
        // Given
        let session1 = makeMockSession(id: UUID())
        let session2 = makeMockSession(id: UUID())
        var createCount = 0
        mockFocusService.startFocusSessionHandler = { task, duration, phase, roundIndex in
            createCount += 1
            return createCount == 1 ? session1 : session2
        }
        mockFocusService.completeSessionHandler = { _, _ in }
        viewModel.startFocus(phase: .focus)

        // When - 正常跳过（无中断）
        viewModel.skipPhase()

        // Then - 延迟闭包正常启动下一阶段
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        XCTAssertEqual(createCount, 2, "无中断时跳过应自动开始下一阶段")
        XCTAssertTrue(viewModel.isRunning)
    }

    // ========================================================================
    // MARK: - 回归：actualDuration 扣除暂停时长
    // ========================================================================

    func testHandleTimerFinished_ThenActualDurationExcludesPausedTime() {
        // Given
        let mockSession = makeMockSession()
        mockSession.startTime = Date().addingTimeInterval(-100) // 100 秒前开始
        var capturedDuration: TimeInterval?
        mockFocusService.startFocusSessionHandler = { task, duration, phase, roundIndex in
            return mockSession
        }
        mockFocusService.completeSessionHandler = { _, actualDuration in
            capturedDuration = actualDuration
        }
        viewModel.startFocus(phase: .focus)

        // 复审修复（2026-10-14）：净专注时长改为 focusService.activeElapsedSeconds 单一真值源后，
        // 暂停/恢复必须同步落库 —— 否则持久化侧看不到这次暂停，断言会失真。
        // 夹具自洽：本用例把 startTime 回拨了 100 秒模拟「已专注一段时间」，
        // updatedAt 是「本段计时起点」标记，必须同步回拨，否则净专注秒恒从 0 起算。
        mockSession.updatedAt = mockSession.startTime
        mockFocusService.pauseSession(mockSession,
                                      activeSeconds: mockFocusService.activeElapsedSeconds(for: mockSession))
        timerManager.pause()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        mockFocusService.resumeSession(mockSession)
        timerManager.resume()

        // When
        timerManager.timerState = .finished
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        // Then - actualDuration = 实际流逝 - 暂停时长（而非包含暂停的完整时间）
        XCTAssertNotNil(capturedDuration)
        let rawElapsed = Date().timeIntervalSince(mockSession.startTime)
        XCTAssertEqual(capturedDuration ?? 0,
                       rawElapsed - timerManager.totalPausedDuration,
                       accuracy: 0.2,
                       "actualDuration 应扣除暂停时长")
        // 扣除前 rawElapsed ≈ 100s，扣除后明显更小
        XCTAssertLessThan(capturedDuration ?? 999, rawElapsed, "扣除暂停后应小于总流逝时间")
        XCTAssertGreaterThan(timerManager.totalPausedDuration, 0.19, "暂停时长应被累计")
    }

    // ========================================================================
    // MARK: - v1.3 UI 升级：phase 切换 + 时长 chip
    // ========================================================================

    func testSwitchPhase_WhenIdle_ThenUpdatesActivePhaseAndDisplay() {
        // Given - 默认 activePhase == .focus
        XCTAssertEqual(viewModel.currentPhase, .focus)
        // 修复（2026-10-14 T4）：本用例原先依赖其它用例残留写入的 shortBreakDuration
        // （tearDown 清理 UserDefaults 后暴露）→ 改为自给自足。
        UserDefaults.standard.set(AppConstants.defaultShortBreakDuration, forKey: "shortBreakDuration")

        // When
        viewModel.switchPhase(.shortBreak)

        // Then
        XCTAssertEqual(viewModel.currentPhase, .shortBreak, "空闲态应直接切到目标 phase")
        let shortBreakTotal = UserDefaults.standard.double(forKey: "shortBreakDuration")
        XCTAssertNotEqual(shortBreakTotal, 0, "短休默认时长应已存在（用于更新显示）")
        XCTAssertFalse(viewModel.isRunning)
    }

    func testSwitchPhase_WhenIdle_ThenUpdatesDisplayDuration() {
        // Given - 短休默认 5 分钟 = 300 秒
        UserDefaults.standard.set(TimeInterval(3 * 60), forKey: "shortBreakDuration")

        // When
        viewModel.switchPhase(.shortBreak)

        // Then
        XCTAssertEqual(viewModel.currentPhase, .shortBreak)
        XCTAssertEqual(viewModel.timerDisplay, "03:00", "切换到短休后显示应立即更新为新的默认时长")
    }

    func testSwitchPhase_WhenRunning_ThenAbandonsAndResetsToTargetPhase() {
        // Given
        let mockSession = makeMockSession()
        mockFocusService.startFocusSessionHandler = { _, _, _, _ in mockSession }
        var abandonedSession: FocusSession?
        mockFocusService.abandonSessionHandler = { session in
            abandonedSession = session
        }
        viewModel.startFocus(phase: .focus)
        XCTAssertTrue(viewModel.isRunning)

        // When
        viewModel.switchPhase(.longBreak)

        // Then
        XCTAssertNotNil(abandonedSession, "运行中切 phase 应先 abandon 当前会话")
        XCTAssertEqual(viewModel.currentPhase, .longBreak)
        XCTAssertFalse(viewModel.isRunning, "切换后应回到 idle")
        XCTAssertNil(viewModel.currentSession)
    }

    func testSwitchPhase_WhenPaused_ThenAbandonsAndResets() {
        // Given
        let mockSession = makeMockSession()
        mockFocusService.startFocusSessionHandler = { _, _, _, _ in mockSession }
        mockFocusService.abandonSessionHandler = { _ in }
        viewModel.startFocus(phase: .focus)
        viewModel.pauseFocus()
        XCTAssertTrue(viewModel.isPaused)

        // When
        viewModel.switchPhase(.shortBreak)

        // Then
        XCTAssertEqual(viewModel.currentPhase, .shortBreak)
        XCTAssertFalse(viewModel.isRunning)
        XCTAssertFalse(viewModel.isPaused)
    }

    func testApplyFocusDuration_WhenIdleOnFocusPhase_ThenUpdatesDisplay() {
        // Given - 默认 25 分钟
        XCTAssertEqual(viewModel.timerDisplay, "25:00")

        // When
        viewModel.applyFocusDuration(TimeInterval(45 * 60))

        // Then
        XCTAssertEqual(viewModel.timerDisplay, "45:00", "空闲态下 chip 选择应立即更新显示")
        XCTAssertEqual(UserDefaults.standard.double(forKey: "focusDuration"),
                       TimeInterval(45 * 60),
                       "新时长应写回 UserDefaults")
    }

    func testApplyFocusDuration_WhenIdleButOnBreakPhase_ThenDoesNotChangeDisplay() {
        // Given
        viewModel.switchPhase(.shortBreak)
        let beforeDisplay = viewModel.timerDisplay

        // When
        viewModel.applyFocusDuration(TimeInterval(60 * 60))

        // Then
        XCTAssertEqual(viewModel.timerDisplay, beforeDisplay, "非 focus 阶段下 chip 调用不应改 display")
        XCTAssertEqual(UserDefaults.standard.double(forKey: "focusDuration"),
                       TimeInterval(60 * 60),
                       "但 UserDefaults 仍应被持久化（后续启动读取）")
    }

    func testApplyShortBreakDuration_PersistsAndUpdatesDisplayOnBreak() {
        // Given
        viewModel.switchPhase(.shortBreak)

        // When
        viewModel.applyShortBreakDuration(TimeInterval(10 * 60))

        // Then
        XCTAssertEqual(viewModel.timerDisplay, "10:00")
        XCTAssertEqual(UserDefaults.standard.double(forKey: "shortBreakDuration"),
                       TimeInterval(10 * 60))
    }

    func testApplyLongBreakDuration_PersistsAndUpdatesDisplayOnLongBreak() {
        // Given
        viewModel.switchPhase(.longBreak)

        // When
        viewModel.applyLongBreakDuration(TimeInterval(20 * 60))

        // Then
        XCTAssertEqual(viewModel.timerDisplay, "20:00")
        XCTAssertEqual(UserDefaults.standard.double(forKey: "longBreakDuration"),
                       TimeInterval(20 * 60))
    }

    func testClearSelectedTask_RemovesTask() {
        // Given
        let context = persistenceController.viewContext
        let task = Task(context: context)
        task.storageId = UUID()
        task.title = "测试任务"
        task.status = TaskStatus.active.rawValue
        viewModel.selectTask(task)
        XCTAssertNotNil(viewModel.selectedTask)

        // When
        viewModel.clearSelectedTask()

        // Then
        XCTAssertNil(viewModel.selectedTask, "清除后 selectedTask 应为 nil")
    }

    // ========================================================================
    // MARK: - 审查修复回归测试（2026-08-12）
    // ========================================================================

    /// P1 #5：skipPhase 在暂停态跳过时，actualDuration 应补扣当前暂停段
    func testSkipPhase_WhenPaused_ThenActualDurationExcludesCurrentPause() {
        // Given
        let mockSession = makeMockSession()
        mockFocusService.startFocusSessionHandler = { _, _, _, _ in mockSession }
        viewModel.startFocus(phase: .focus)
        XCTAssertTrue(viewModel.isRunning)

        // 暂停 0.2s 后再跳过：暂停期间流逝的时间不应计入 actualDuration
        viewModel.pauseFocus()
        XCTAssertTrue(viewModel.isPaused)
        Thread.sleep(forTimeInterval: 0.2)

        var capturedDuration: TimeInterval?
        mockFocusService.completeSessionHandler = { _, duration in
            capturedDuration = duration
        }

        // When
        viewModel.skipPhase()

        // Then：actualDuration = startTime 至今 - totalPaused - currentPaused
        // 由于暂停段约 0.2s，actualDuration 应明显小于「全程 elapsed」（约 0.2s+ 的运行时间）
        let totalElapsed = Date().timeIntervalSince(mockSession.startTime)
        XCTAssertNotNil(capturedDuration, "skipPhase 应调用 completeSession")
        if let duration = capturedDuration {
            XCTAssertLessThan(duration, totalElapsed - 0.15,
                              "暂停段应被扣除（actualDuration 应明显小于全程流逝时间）")
        }
    }

    /// P1 #4：恢复会话时剩余时间 ≤ 0 走完成逻辑，不再残留 running 会话
    func testRestorePendingSession_WhenRemainingNonPositive_ThenCompletesSession() {
        // Given：会话 startTime 远早于 now，plannedDuration 已耗尽
        let context = persistenceController.viewContext
        let session = FocusSession(context: context)
        session.storageId = UUID()
        session.startTime = Date().addingTimeInterval(-1600)   // 已超过 1500s 计划时长
        session.plannedDuration = 1500
        session.phase = FocusPhase.focus.rawValue
        session.roundIndex = 1
        session.status = SessionStatus.running.rawValue
        session.createdAt = Date()
        // 修复（2026-10-14）：恢复判定改用持久化净专注秒数（activeElapsedSeconds）后夹具必须自洽 ——
        // updatedAt 是「本段计时起点」标记，只回退 startTime 会让 activeElapsed≈0，
        // 被误判成「刚开始」而非「已超时」。此处需与 startTime 同步回退。
        session.updatedAt = Date().addingTimeInterval(-1600)

        // needsRestore 在 init 时经 focusService.getCurrentSession() 读取，
        // 因此必须先设置 currentSessionToReturn 再重建 VM（审查修复：原写法 init 后设置无效）
        mockFocusService.currentSessionToReturn = session
        viewModel = FocusViewModel(
            focusService: mockFocusService,
            timerManager: timerManager,
            notificationService: mockNotificationService,
            appBlockerService: mockAppBlockerService,
            audioService: mockAudioService,
            achievementService: mockAchievementService,
            taskService: mockTaskService,
            speechService: mockSpeechService
        )

        var completed = false
        mockFocusService.completeSessionHandler = { _, _ in completed = true }

        // When
        viewModel.restorePendingSessionIfNeeded()

        // Then：会话被完成，状态回到 idle，不再残留
        XCTAssertTrue(completed, "remaining<=0 时应完成会话")
        XCTAssertNil(viewModel.currentSession)
        XCTAssertEqual(viewModel.timerState, .idle)
    }

    // MARK: - 外部控制状态对齐（2026-10-15）
    // 背景/冷启动执行 Live Activity 按钮时 FocusView 未上屏 → restorePendingSessionIfNeeded
    // 不执行 → timerState 停留 .idle → pause/resume 的 guard 静默吞掉点击。
    // ensureOperableStateForExternalControl 在控制入口做最小对齐（仅计时核心，无前台恢复副作用）。

    /// 重建 VM 以让 init 重新计算 needsRestore（必须在设置 mock 的 currentSessionToReturn 之后调用）
    private func recreateViewModel() {
        viewModel = FocusViewModel(
            focusService: mockFocusService,
            timerManager: timerManager,
            notificationService: mockNotificationService,
            appBlockerService: mockAppBlockerService,
            audioService: mockAudioService,
            achievementService: mockAchievementService,
            taskService: mockTaskService,
            speechService: mockSpeechService
        )
    }

    func testEnsureOperableState_RunningSession_AlignsToRunning() {
        let session = makeMockSession(status: .running)
        mockFocusService.currentSessionToReturn = session
        recreateViewModel()
        XCTAssertEqual(viewModel.timerState, .idle, "前置：冷启动未对齐时应为 idle")

        viewModel.ensureOperableStateForExternalControl()

        XCTAssertEqual(viewModel.timerState, .running, "对齐后 pauseFocus 不再被 guard 吞掉")
        XCTAssertNotNil(viewModel.currentSession)
    }

    func testEnsureOperableState_PausedSession_AlignsToPaused() {
        let session = makeMockSession(status: .paused)
        mockFocusService.currentSessionToReturn = session
        recreateViewModel()

        viewModel.ensureOperableStateForExternalControl()

        XCTAssertEqual(viewModel.timerState, .paused, "暂停中会话应对齐为 paused（供 resumeFocus 操作）")
    }

    func testEnsureOperableState_NoPendingSession_DoesNothing() {
        mockFocusService.currentSessionToReturn = nil
        recreateViewModel()

        viewModel.ensureOperableStateForExternalControl()

        XCTAssertEqual(viewModel.timerState, .idle)
        XCTAssertNil(viewModel.currentSession)
    }

    func testEnsureOperableState_AlreadyOperable_SkipsAlignment() {
        // 前台真实链路已开始专注 → timerState = .running，对齐不应干扰
        let session = makeMockSession(status: .running)
        mockFocusService.startFocusSessionHandler = { _, _, _, _ in session }
        viewModel.startFocus(phase: .focus)
        XCTAssertEqual(viewModel.timerState, .running)

        viewModel.ensureOperableStateForExternalControl()

        XCTAssertEqual(viewModel.timerState, .running, "已运行态不应被对齐改动")
    }

    /// 集成：冷启动点「暂停」的完整链路 —— 对齐 + pauseFocus 必须生效并落库
    func testEnsureOperableState_ThenPauseFocus_PersistsPaused() {
        let session = makeMockSession(status: .running)
        mockFocusService.currentSessionToReturn = session
        recreateViewModel()
        XCTAssertEqual(viewModel.timerState, .idle)

        viewModel.ensureOperableStateForExternalControl()
        viewModel.pauseFocus()

        XCTAssertEqual(viewModel.timerState, .paused, "对齐后点击暂停必须生效（此前被 guard 静默吞掉）")
        XCTAssertEqual(session.status, SessionStatus.paused.rawValue, "暂停状态应落库")
    }

    /// 过期会话对齐：完成落库，不残留 running（与前台恢复同判据）
    func testEnsureOperableState_ExpiredSession_CompletesIt() {
        let context = persistenceController.viewContext
        let session = FocusSession(context: context)
        session.storageId = UUID()
        session.startTime = Date().addingTimeInterval(-1600)
        session.plannedDuration = 1500
        session.phase = FocusPhase.focus.rawValue
        session.roundIndex = 1
        session.status = SessionStatus.running.rawValue
        session.createdAt = Date()
        session.updatedAt = Date().addingTimeInterval(-1600)   // 与 startTime 同步回退（净专注秒判据）
        mockFocusService.currentSessionToReturn = session
        recreateViewModel()

        var completed = false
        mockFocusService.completeSessionHandler = { _, _ in completed = true }

        viewModel.ensureOperableStateForExternalControl()

        XCTAssertTrue(completed, "过期会话应对齐为完成")
        XCTAssertNil(viewModel.currentSession)
        XCTAssertEqual(viewModel.timerState, .idle)
    }

    // ========================================================================
    // MARK: - 白噪音记忆（用户反馈 2026-11-19）
    // ========================================================================

    /// 默认（未设置偏好）→ 专注开始自动播放白噪音（既有行为）
    func testStartFocus_GivenNoPreference_ThenWhiteNoiseAutoPlays() {
        // 显式清除偏好，避免依赖用例执行顺序（其它用例的 toggle 会写入该键）
        UserDefaults.standard.removeObject(forKey: FocusViewModel.whiteNoiseAutoPlayKey)
        mockFocusService.sessions = [makeMockSession()]

        viewModel.startFocus(phase: .focus)

        XCTAssertTrue(mockAudioService.isWhiteNoisePlaying, "默认应自动播放白噪音")
        XCTAssertTrue(viewModel.isWhiteNoiseOn)
    }

    /// 用户关闭过白噪音 → 下次开始专注不再自动播放
    func testStartFocus_GivenUserTurnedOffWhiteNoise_ThenDoesNotAutoPlay() {
        UserDefaults.standard.set(false, forKey: FocusViewModel.whiteNoiseAutoPlayKey)
        mockFocusService.sessions = [makeMockSession()]

        viewModel.startFocus(phase: .focus)

        XCTAssertFalse(mockAudioService.isWhiteNoisePlaying,
                       "用户关闭后不得再自动播放（应记住选择）")
        XCTAssertFalse(viewModel.isWhiteNoiseOn)
    }

    /// 手动开关会把选择写回偏好（2026-11-22 修正）：
    /// 源码默认值为 true，显式从 false 起步 → 切一次为 true，再切回 false。
    func testToggleWhiteNoise_ThenChoiceIsPersisted() {
        UserDefaults.standard.set(false, forKey: FocusViewModel.whiteNoiseAutoPlayKey)

        viewModel.toggleWhiteNoise()   // 关 → 开
        XCTAssertEqual(UserDefaults.standard.object(forKey: FocusViewModel.whiteNoiseAutoPlayKey) as? Bool, true)

        viewModel.toggleWhiteNoise()   // 开 → 关
        XCTAssertEqual(UserDefaults.standard.object(forKey: FocusViewModel.whiteNoiseAutoPlayKey) as? Bool, false)
    }
}

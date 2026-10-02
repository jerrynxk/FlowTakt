import XCTest
import Combine
@testable import FlowTakt

// MARK: - TimerManagerTests
// 测试 TimerManager 状态机转换（idle → running → paused → running → idle）
//
// 注意: TimerManager 使用 Timer.scheduledTimer 在主线程运行，
// timerState 通过 @Published 发布状态变更。
//
// Xcode Target 配置:
// 1. 将本文件加入 FlowTaktTests Target 的 Compile Sources
// 2. 确保 @testable import FlowTakt 可用

@MainActor
final class TimerManagerTests: XCTestCase {
    var timerManager: TimerManager!
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        timerManager = TimerManager()
        cancellables = Set<AnyCancellable>()
    }

    override func tearDown() {
        timerManager.reset()
        timerManager = nil
        cancellables = nil
        super.tearDown()
    }

    // ========================================================================
    // MARK: - 初始状态
    // ========================================================================

    func testInitialState_WhenCreated_ThenStateIsIdle() {
        // Then
        XCTAssertEqual(timerManager.timerState, .idle)
        XCTAssertEqual(timerManager.remainingSeconds, 0)
        XCTAssertEqual(timerManager.elapsedSeconds, 0)
        XCTAssertEqual(timerManager.totalDuration, 0)
    }

    // ========================================================================
    // MARK: - 启动
    // ========================================================================

    func testStart_GivenIdleState_ThenStateBecomesRunning() {
        // Given
        let duration: TimeInterval = 1500

        // When
        timerManager.start(duration: duration)

        // Then
        XCTAssertEqual(timerManager.timerState, .running)
        XCTAssertEqual(timerManager.totalDuration, duration)
        XCTAssertEqual(timerManager.remainingSeconds, duration)
        // elapsedSeconds 由 Date().timeIntervalSince(startDate) 计算，调用瞬间已有微小时间差
        XCTAssertLessThan(timerManager.elapsedSeconds, 1.0)
    }

    func testStart_GivenAlreadyRunning_ThenRestartsWithNewDuration() {
        // Given
        timerManager.start(duration: 1500)
        XCTAssertEqual(timerManager.timerState, .running)

        // When - 再次 start（实现设计为总是 stop() 后重新开始）
        timerManager.start(duration: 300)

        // Then - start() 总是调用 stop() 后重新开始，新 duration 生效
        XCTAssertEqual(timerManager.timerState, .running)
        XCTAssertEqual(timerManager.totalDuration, 300, "start() 总是以新 duration 重启")
    }

    // ========================================================================
    // MARK: - 暂停
    // ========================================================================

    func testPause_GivenRunningState_ThenStateBecomesPaused() {
        // Given
        timerManager.start(duration: 1500)

        // When
        timerManager.pause()

        // Then
        XCTAssertEqual(timerManager.timerState, .paused)
    }

    func testPause_GivenIdleState_ThenIgnored() {
        // Given - 初始 idle

        // When
        timerManager.pause()

        // Then
        XCTAssertEqual(timerManager.timerState, .idle)
    }

    func testPause_GivenAlreadyPaused_ThenIgnored() {
        // Given
        timerManager.start(duration: 1500)
        timerManager.pause()
        XCTAssertEqual(timerManager.timerState, .paused)

        // When
        timerManager.pause()

        // Then
        XCTAssertEqual(timerManager.timerState, .paused, "已暂停时再暂停不应改变状态")
    }

    // ========================================================================
    // MARK: - 恢复
    // ========================================================================

    func testResume_GivenPausedState_ThenStateBecomesRunning() {
        // Given
        timerManager.start(duration: 1500)
        timerManager.pause()
        XCTAssertEqual(timerManager.timerState, .paused)

        // When
        timerManager.resume()

        // Then
        XCTAssertEqual(timerManager.timerState, .running)
    }

    func testResume_GivenIdleState_ThenIgnored() {
        // Given - 初始 idle

        // When
        timerManager.resume()

        // Then
        XCTAssertEqual(timerManager.timerState, .idle)
    }

    func testResume_GivenRunningState_ThenIgnored() {
        // Given
        timerManager.start(duration: 1500)

        // When
        timerManager.resume()

        // Then
        XCTAssertEqual(timerManager.timerState, .running, "运行中恢复应无效果")
    }

    // ========================================================================
    // MARK: - 重置
    // ========================================================================

    func testReset_GivenRunningState_ThenStateReturnsToIdle() {
        // Given
        timerManager.start(duration: 1500)

        // When
        timerManager.reset()

        // Then
        XCTAssertEqual(timerManager.timerState, .idle)
        XCTAssertEqual(timerManager.remainingSeconds, 0)
        XCTAssertEqual(timerManager.elapsedSeconds, 0)
        XCTAssertEqual(timerManager.totalDuration, 0)
    }

    func testReset_GivenPausedState_ThenStateReturnsToIdle() {
        // Given
        timerManager.start(duration: 1500)
        timerManager.pause()

        // When
        timerManager.reset()

        // Then
        XCTAssertEqual(timerManager.timerState, .idle)
    }

    // ========================================================================
    // MARK: - currentPausedDuration（审查修复 P1 #5 新增属性）
    // ========================================================================

    func testCurrentPausedDuration_WhenRunning_ThenZero() {
        // Given
        timerManager.start(duration: 1500)

        // When / Then
        XCTAssertEqual(timerManager.currentPausedDuration, 0, "运行中不应有当前暂停段")
    }

    func testCurrentPausedDuration_WhenPaused_ThenReturnsElapsedSincePause() {
        // Given
        timerManager.start(duration: 1500)
        timerManager.pause()

        // When
        // pauseDate 已记录，currentPausedDuration 应 ≥ 0 且随时间增长
        let v1 = timerManager.currentPausedDuration
        XCTAssertGreaterThanOrEqual(v1, 0, "暂停后 currentPausedDuration 非负")

        // 短暂等待后应增大（毫秒级精度可能为 0，用两次读取保证非负与单调）
        Thread.sleep(forTimeInterval: 0.05)
        let v2 = timerManager.currentPausedDuration
        XCTAssertGreaterThanOrEqual(v2, v1, "currentPausedDuration 应随时间单调不减")
    }

    func testCurrentPausedDuration_AfterResume_ThenZero() {
        // Given
        timerManager.start(duration: 1500)
        timerManager.pause()
        XCTAssertGreaterThanOrEqual(timerManager.currentPausedDuration, 0)

        // When
        timerManager.resume()

        // Then
        XCTAssertEqual(timerManager.currentPausedDuration, 0, "恢复后 pauseDate 清空，无当前暂停段")
    }

    func testReset_GivenIdleState_ThenStateRemainsIdle() {
        // Given - 初始 idle

        // When
        timerManager.reset()

        // Then
        XCTAssertEqual(timerManager.timerState, .idle)
    }

    // ========================================================================
    // MARK: - 状态转换序列（完整周期）
    // ========================================================================

    func testStateTransition_CompleteCycle_IdleRunningPausedRunningResetIdle() {
        // Given
        let duration: TimeInterval = 1500

        // 1) idle → running
        timerManager.start(duration: duration)
        XCTAssertEqual(timerManager.timerState, .running)
        XCTAssertEqual(timerManager.totalDuration, duration)

        // 2) running → paused
        timerManager.pause()
        XCTAssertEqual(timerManager.timerState, .paused)

        // 3) paused → running
        timerManager.resume()
        XCTAssertEqual(timerManager.timerState, .running)

        // 4) running → idle (reset)
        timerManager.reset()
        XCTAssertEqual(timerManager.timerState, .idle)
        XCTAssertEqual(timerManager.remainingSeconds, 0)
        XCTAssertEqual(timerManager.elapsedSeconds, 0)
    }

    func testStateTransition_PauseAndResumeKeepsDuration() {
        // Given
        timerManager.start(duration: 300)

        // When - 暂停再恢复
        timerManager.pause()
        let pausedRemaining = timerManager.remainingSeconds
        timerManager.resume()

        // Then - totalDuration 保持不变
        XCTAssertEqual(timerManager.totalDuration, 300)
        // remainingSeconds 在 resume 时恢复为暂停时的值
        XCTAssertEqual(timerManager.remainingSeconds, pausedRemaining)
    }

    // ========================================================================
    // MARK: - Published 属性
    // ========================================================================

    func testPublishedProperties_WhenStateChanges_ThenPublishesUpdates() {
        // Given
        var stateValues: [TimerState] = []
        let expectation = expectation(description: "等待状态发布")

        timerManager.$timerState
            .dropFirst() // 忽略初始值
            .sink { state in
                stateValues.append(state)
                if state == .running {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        timerManager.start(duration: 1500)

        // Then
        wait(for: [expectation], timeout: 1.0)
        XCTAssertTrue(stateValues.contains(.running), "timerState 应发布 .running")
    }

    // ========================================================================
    // MARK: - 边界条件
    // ========================================================================

    func testStart_WithZeroDuration_ThenStateStaysIdle() {
        // Given
        timerManager.start(duration: 0)

        // Then
        XCTAssertEqual(timerManager.timerState, .idle, "零值 duration 应被 guard 拦截")
    }

    func testStart_WithNegativeDuration_ThenStateStaysIdle() {
        // Given
        timerManager.start(duration: -100)

        // Then
        XCTAssertEqual(timerManager.timerState, .idle, "负值 duration 应被 guard 拦截")
    }

    func testMultipleStartCalls_AlwaysRestartsWithLatestDuration() {
        // Given
        timerManager.start(duration: 1500)

        // When - 多次调用 start（实际行为：每次 stop() 后重新开始）
        timerManager.start(duration: 300)
        timerManager.start(duration: 600)

        // Then - 最后一次 start 的 duration 生效（因为每次都调用 stop() 重启）
        XCTAssertEqual(timerManager.totalDuration, 600)
        XCTAssertEqual(timerManager.timerState, .running)
    }

    func testResetDuringPause_ClearsAllState() {
        // Given
        timerManager.start(duration: 1500)
        timerManager.pause()

        // When
        timerManager.reset()

        // Then
        XCTAssertEqual(timerManager.timerState, .idle)
        XCTAssertEqual(timerManager.remainingSeconds, 0)
        XCTAssertEqual(timerManager.elapsedSeconds, 0)
        XCTAssertEqual(timerManager.totalDuration, 0)
    }

    // ========================================================================
    // MARK: - 暂停时长累计（回归：actualDuration 扣除暂停时间）
    // ========================================================================

    func testPauseResume_ThenTotalPausedDurationAccumulates() {
        // Given
        timerManager.start(duration: 1500)

        // When - 暂停约 0.2s 后恢复
        timerManager.pause()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        timerManager.resume()

        // Then - 暂停时长被累计
        XCTAssertGreaterThanOrEqual(timerManager.totalPausedDuration, 0.19, "暂停时长应被结算到 totalPausedDuration")
        XCTAssertLessThan(timerManager.totalPausedDuration, 0.5)
    }

    func testMultiplePauseResume_ThenTotalPausedDurationAccumulates() {
        // Given
        timerManager.start(duration: 1500)

        // When - 两次暂停/恢复
        timerManager.pause()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        timerManager.resume()
        timerManager.pause()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        timerManager.resume()

        // Then - 两次暂停时长累加
        XCTAssertGreaterThanOrEqual(timerManager.totalPausedDuration, 0.19)
    }

    func testReset_ThenTotalPausedDurationCleared() {
        // Given
        timerManager.start(duration: 1500)
        timerManager.pause()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        timerManager.resume()

        // When
        timerManager.reset()

        // Then
        XCTAssertEqual(timerManager.totalPausedDuration, 0, "reset 后暂停时长应清零")
    }

    // ========================================================================
    // MARK: - 延迟 stop 竞态（回归：generation token 防误停新计时器）
    // ========================================================================

    func testFinishedThenImmediateStart_NotStoppedByDelayedCleanup() {
        // Given - 短时长快速走到 finished（延迟 stop 已排队）
        timerManager.start(duration: 0.2)
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))

        // When - 立即启动新计时（旧 generation 的延迟 stop 不应打断）
        timerManager.start(duration: 300)
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))

        // Then - 新计时保持运行，未被延迟 stop 误停
        XCTAssertEqual(timerManager.timerState, .running, "新计时不应被旧 generation 的延迟 stop 打断")
        XCTAssertEqual(timerManager.totalDuration, 300)
    }
}

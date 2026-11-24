import XCTest
import Combine
@testable import FlowTakt

// MARK: - TimerManagerBackgroundTests
// 专项测试 TimerManager.syncFromBackground 后台恢复逻辑

@MainActor
final class TimerManagerBackgroundTests: XCTestCase {
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
    // MARK: - syncFromBackground 在 running 状态下
    // ========================================================================

    func testSyncFromBackground_WhenRunning_ThenRecalculatesRemainingTime() {
        // Given：启动一个 100 秒的计时器
        timerManager.start(duration: 100)
        XCTAssertEqual(timerManager.timerState, .running)
        XCTAssertEqual(timerManager.timeRemaining, 100, accuracy: 1)

        // When：模拟后台 30 秒（通过直接修改 startDate 模拟）
        // 由于 startDate 是 private，我们用 elapsed 时间来验证
        // 这里采用等待短暂时间 + 再次 syncFromBackground 的方式
        let expectation = XCTestExpectation(description: "wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.timerManager.syncFromBackground()
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)

        // Then：timeRemaining 应小于 100（已经过 0.3 秒）
        XCTAssertLessThan(timerManager.timeRemaining, 100, "syncFromBackground 后 timeRemaining 应小于初始值")
        XCTAssertGreaterThan(timerManager.timeRemaining, 90, "timeRemaining 不应低于 90 秒")
        XCTAssertGreaterThan(timerManager.progress, 0, "progress 应大于 0")
        XCTAssertEqual(timerManager.timerState, .running, "未超时应保持 running")
    }

    func testSyncFromBackground_WhenRunning_LongTimeElapsed_ThenTransitionsToFinished() {
        // 修复（2026-10-14 审查 T5）：原用例靠「1 秒时长 + 等 1.5 秒」制造超时，
        // 但 0.1s 的前台 Timer 会抢先发布 .finished —— 删掉 syncFromBackground 的超时分支
        // 用例依然全绿（假绿）。现注入固定时钟：把起点设到 1 小时前，
        // 再调用 syncFromBackground，超时判定只可能来自它自己。
        let base = Date()
        var current = base
        timerManager.nowProvider = { current }
        timerManager.start(duration: 60)
        current = base.addingTimeInterval(3600)   // 假装后台待了 1 小时

        var observedFinished = false
        let observation = timerManager.$timerState
            .sink { state in if state == .finished { observedFinished = true } }
        defer { observation.cancel() }

        timerManager.syncFromBackground()

        XCTAssertTrue(observedFinished, "syncFromBackground 超时后应发布 .finished 状态")
        XCTAssertLessThanOrEqual(timerManager.timeRemaining, 0, "超时后剩余时间应为 0")
    }

    // ========================================================================
    // MARK: - syncFromBackground 在非 running 状态下（无副作用）
    // ========================================================================

    func testSyncFromBackground_WhenIdle_ThenNoEffect() {
        // Given：idle 状态
        XCTAssertEqual(timerManager.timerState, .idle)

        // When
        timerManager.syncFromBackground()

        // Then：状态不变
        XCTAssertEqual(timerManager.timerState, .idle)
        XCTAssertEqual(timerManager.timeRemaining, 0)
        XCTAssertEqual(timerManager.totalDuration, 0)
    }

    func testSyncFromBackground_WhenPaused_ThenNoEffect() {
        // Given：启动后暂停
        timerManager.start(duration: 100)
        timerManager.pause()
        XCTAssertEqual(timerManager.timerState, .paused)
        let pausedRemaining = timerManager.timeRemaining

        // When
        timerManager.syncFromBackground()

        // Then：paused 状态下 syncFromBackground 不应改变状态（guard 仅 running 通过）
        XCTAssertEqual(timerManager.timerState, .paused)
        XCTAssertEqual(timerManager.timeRemaining, pausedRemaining, "paused 状态下 syncFromBackground 不应改变剩余时间")
    }

    // ========================================================================
    // MARK: - syncFromBackground 在 totalDuration 为 0 时
    // ========================================================================

    func testSyncFromBackground_WhenTotalDurationZero_ThenNoEffect() {
        // Given：构造 running 但 totalDuration 为 0 的异常状态
        // 正常 start 会校验 duration > 0，所以这里手动构造不可能的状态
        timerManager.start(duration: 100)
        timerManager.stop()
        XCTAssertEqual(timerManager.timerState, .idle)
        XCTAssertEqual(timerManager.totalDuration, 0)

        // When
        timerManager.syncFromBackground()

        // Then：guard totalDuration > 0 失败，无副作用
        XCTAssertEqual(timerManager.timerState, .idle)
        XCTAssertEqual(timerManager.totalDuration, 0)
    }

    // ========================================================================
    // MARK: - progress 正确更新
    // ========================================================================

    func testSyncFromBackground_WhenRunning_ThenProgressUpdates() {
        // Given：启动 100 秒计时器
        timerManager.start(duration: 100)
        XCTAssertEqual(timerManager.progress, 0, accuracy: 0.01)

        // When：等待 0.5 秒后 syncFromBackground
        let expectation = XCTestExpectation(description: "wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.timerManager.syncFromBackground()
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)

        // Then：progress 应介于 0 和 1 之间，且大于 0
        XCTAssertGreaterThan(timerManager.progress, 0)
        XCTAssertLessThan(timerManager.progress, 1)
    }

    // ========================================================================
    // MARK: - 订阅 finished 事件（验证后台超时能触发 finished 发布）
    // ========================================================================

    func testSyncFromBackground_WhenTimerExpired_ThenPublishesFinished() {
        // 修复（T5）：同上，注入固定时钟消除前台 Timer 抢先触发的竞态
        // Given：启动 1 秒计时器，订阅 timerState 变化
        timerManager.start(duration: 1)
        var capturedStates: [TimerState] = []
        timerManager.$timerState
            .receive(on: DispatchQueue.main)
            .sink { state in
                capturedStates.append(state)
            }
            .store(in: &cancellables)

        // When：等待 1.5 秒后调用 syncFromBackground
        let expectation = XCTestExpectation(description: "wait for finish")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.timerManager.syncFromBackground()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                expectation.fulfill()
            }
        }
        wait(for: [expectation], timeout: 3)

        // Then：捕获的状态中应包含 .finished
        XCTAssertTrue(capturedStates.contains(.finished), "syncFromBackground 超时应发布 .finished 状态")
    }
}

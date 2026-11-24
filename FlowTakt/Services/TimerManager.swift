import Foundation
import Combine

// MARK: - 计时器状态

enum TimerState: Equatable {
    case idle
    case running
    case paused
    case finished
}

// MARK: - 计时器管理器（支持后台运行）

@MainActor
final class TimerManager: ObservableObject {
    @Published var timeRemaining: TimeInterval = 0
    @Published var timerState: TimerState = .idle
    @Published var progress: Double = 0

    private(set) var totalDuration: TimeInterval = 0
    private var timer: Timer?
    private var startDate: Date?
    private var pausedTimeRemaining: TimeInterval = 0
    private var pauseDate: Date?
    /// 本计时周期累计暂停时长（秒）：resume 时结算，供 ViewModel 计算实际专注时长时扣除
    private(set) var totalPausedDuration: TimeInterval = 0
    /// 计时代际计数：每次 start/stop 递增；延迟 stop 闭包用 token 校验，
    /// 避免「发布 .finished 后的延迟 stop」误停掉窗口内新启动的计时器
    private var generation = 0

    // MARK: - 测试时钟注入（修复 2026-10-14 审查 T5）
    //
    // 此前 `syncFromBackground` 的两条用例用「1 秒时长 + 等 1.5 秒」制造超时，
    // 但 0.1s 的前台 Timer 会**先于** syncFromBackground 自行判定超时并发布 .finished，
    // 于是删掉 syncFromBackground 的整个超时分支，用例依然全绿（假绿）。
    // 注入可控时钟后：startDate 由测试指定，`updateTimer` 走注入的「现在」，
    // 前台 Timer 不再参与判定，超时路径可被确定性地验证。
    /// 时钟源：生产返回 Date()，测试可替换为固定值
    var nowProvider: () -> Date = { Date() }

    /// 手动推进一次计时计算（测试用；不依赖 RunLoop 真实时间）
    func tickForTesting() { updateTimer() }

    /// 测试用：直接设置计时起点（等价于「已经过去了 N 秒」）
    func setStartDateForTesting(_ date: Date) { startDate = date }

    /// 开始计时
    func start(duration: TimeInterval) {
        guard duration > 0 else { return }
        stop()
        generation += 1
        totalDuration = duration
        timeRemaining = duration
        timerState = .running
        startDate = nowProvider()
        scheduleTimer()
    }

    /// 暂停计时
    func pause() {
        guard timerState == .running else { return }
        timer?.invalidate()
        timer = nil
        pausedTimeRemaining = timeRemaining
        pauseDate = nowProvider()
        timerState = .paused
    }

    /// 恢复计时
    func resume() {
        guard timerState == .paused else { return }
        if let pauseDate = pauseDate {
            totalPausedDuration += nowProvider().timeIntervalSince(pauseDate)
        }
        pauseDate = nil
        timerState = .running
        let alreadyElapsed = totalDuration - pausedTimeRemaining
        // 修复（2026-10-15 审查 P1-013）：改用注入时钟，测试可确定性验证 resume 后的连续性
        startDate = nowProvider().addingTimeInterval(-alreadyElapsed)
        scheduleTimer()
    }

    /// 当前暂停段的累计时长（暂停态返回暂停至今的秒数；非暂停态返回 0）。
    /// 审查修复（2026-08-12）：skipPhase 等路径需要在暂停态结算 actualDuration 时补扣。
    var currentPausedDuration: TimeInterval {
        guard let pauseDate else { return 0 }
        // 修复（2026-10-15 审查 P1-013）：改用注入时钟（与 updateTimer 同源，消除测试假绿）
        return nowProvider().timeIntervalSince(pauseDate)
    }

    /// 停止计时
    func stop() {
        generation += 1
        timer?.invalidate()
        timer = nil
        timeRemaining = 0
        totalDuration = 0
        progress = 0
        timerState = .idle
        startDate = nil
        pausedTimeRemaining = 0
        pauseDate = nil
        totalPausedDuration = 0
    }

    // MARK: - 后台支持

    /// 从后台恢复时重新同步（基于 startDate 计算实际剩余时间）
    func syncFromBackground() {
        guard timerState == .running, let start = startDate, totalDuration > 0 else { return }

        let elapsed = nowProvider().timeIntervalSince(start)
        timeRemaining = max(0, totalDuration - elapsed)
        progress = min(1.0, elapsed / totalDuration)

        if timeRemaining <= 0 {
            // 先发布 finished 状态供订阅者处理完成回调，再清理（避免立即 stop 导致状态抖动丢失 finished 信号）
            timerState = .finished
            // 延迟一拍清理，让订阅者能收到 finished 事件；用 generation token 防止误停新计时器
            let gen = generation
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == gen else { return }
                self.stop()
            }
        } else {
            scheduleTimer()
        }
    }

    /// 当前已消耗时间
    var elapsedTime: TimeInterval {
        guard let startDate = startDate else { return 0 }
        // 修复（2026-10-15 审查 P1-013）：改用注入时钟（与 updateTimer 同源，消除测试假绿）
        return nowProvider().timeIntervalSince(startDate)
    }

    /// 剩余秒数（别名，用于测试兼容）
    var remainingSeconds: TimeInterval { timeRemaining }

    /// 已用秒数（别名，用于测试兼容）
    var elapsedSeconds: TimeInterval { elapsedTime }

    /// 重置计时器（别名，用于测试兼容）
    func reset() { stop() }

    // MARK: - 私有方法

    private func scheduleTimer() {
        timer?.invalidate()
        // 使用 Timer(timeInterval:repeats:) 不自动 schedule 的初始化器，
        // 然后手动添加到 RunLoop 的 .common 模式，避免 scheduledTimer + add 导致重复注册
        let newTimer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            // Timer 已通过 RunLoop.main 注册，回调必在主线程触发；
            // 用 assumeIsolated 显式断言主 actor 隔离，消除 nonisolated 闭包调用主 actor 方法的告警
            MainActor.assumeIsolated {
                self?.updateTimer()
            }
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    private func updateTimer() {
        guard let startDate = startDate, totalDuration > 0 else { return }

        let elapsed = nowProvider().timeIntervalSince(startDate)
        timeRemaining = max(0, totalDuration - elapsed)
        progress = min(1.0, elapsed / totalDuration)

        if timeRemaining <= 0 {
            // 先发布 finished 状态，订阅者（FocusViewModel）会处理完成回调
            timerState = .finished
            // 延迟一拍清理，让订阅者能收到 finished 事件后再清理状态；用 generation token 防止误停新计时器
            let gen = generation
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == gen else { return }
                self.stop()
            }
        }
    }

    deinit {
        timer?.invalidate()
    }
}

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

    /// 开始计时
    func start(duration: TimeInterval) {
        guard duration > 0 else { return }
        stop()
        generation += 1
        totalDuration = duration
        timeRemaining = duration
        timerState = .running
        startDate = Date()
        scheduleTimer()
    }

    /// 暂停计时
    func pause() {
        guard timerState == .running else { return }
        timer?.invalidate()
        timer = nil
        pausedTimeRemaining = timeRemaining
        pauseDate = Date()
        timerState = .paused
    }

    /// 恢复计时
    func resume() {
        guard timerState == .paused else { return }
        if let pauseDate = pauseDate {
            totalPausedDuration += Date().timeIntervalSince(pauseDate)
        }
        pauseDate = nil
        timerState = .running
        let alreadyElapsed = totalDuration - pausedTimeRemaining
        startDate = Date().addingTimeInterval(-alreadyElapsed)
        scheduleTimer()
    }

    /// 当前暂停段的累计时长（暂停态返回暂停至今的秒数；非暂停态返回 0）。
    /// 审查修复（2026-08-12）：skipPhase 等路径需要在暂停态结算 actualDuration 时补扣。
    var currentPausedDuration: TimeInterval {
        guard let pauseDate else { return 0 }
        return Date().timeIntervalSince(pauseDate)
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

        let elapsed = Date().timeIntervalSince(start)
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
        return Date().timeIntervalSince(startDate)
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

        let elapsed = Date().timeIntervalSince(startDate)
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

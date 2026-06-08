import Foundation
import Combine

// MARK: - 计时器状态

enum TimerState: Equatable {
    case idle
    case running
    case paused
    case finished
}

// MARK: - 计时器管理器

final class TimerManager: ObservableObject {
    @Published var timeRemaining: TimeInterval = 0
    @Published var timerState: TimerState = .idle
    @Published var progress: Double = 0

    private(set) var totalDuration: TimeInterval = 0
    private var timer: Timer?
    private var startDate: Date?
    private var pausedTimeRemaining: TimeInterval = 0

    /// 开始计时
    func start(duration: TimeInterval) {
        stop()
        totalDuration = duration
        timeRemaining = duration
        timerState = .running
        startDate = Date()

        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateTimer()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    /// 暂停计时
    func pause() {
        guard timerState == .running else { return }
        timer?.invalidate()
        timer = nil
        pausedTimeRemaining = timeRemaining
        timerState = .paused
    }

    /// 恢复计时
    func resume() {
        guard timerState == .paused else { return }
        timerState = .running
        startDate = Date().addingTimeInterval(-(totalDuration - pausedTimeRemaining))

        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateTimer()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    /// 停止计时
    func stop() {
        timer?.invalidate()
        timer = nil
        timeRemaining = 0
        totalDuration = 0
        progress = 0
        timerState = .idle
        startDate = nil
        pausedTimeRemaining = 0
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

    private func updateTimer() {
        guard let startDate = startDate, totalDuration > 0 else { return }

        let elapsed = Date().timeIntervalSince(startDate)
        timeRemaining = max(0, totalDuration - elapsed)
        progress = min(1.0, elapsed / totalDuration)

        if timeRemaining <= 0 {
            timerState = .finished
            stop()
        }
    }

    deinit {
        timer?.invalidate()
    }
}

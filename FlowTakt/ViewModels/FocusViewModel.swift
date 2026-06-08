import Foundation
import Combine
import SwiftUI

// MARK: - FocusViewModel

final class FocusViewModel: ObservableObject {
    // MARK: - Dependencies

    private let focusService: FocusServiceProtocol
    private let timerManager: TimerManager
    private let notificationService: NotificationServiceProtocol
    private let appBlockerService: AppBlockerServiceProtocol
    private let audioService: AudioServiceProtocol
    private let achievementService: AchievementServiceProtocol
    private let taskService: TaskServiceProtocol

    // MARK: - Published Properties

    /// 当前专注会话
    @Published var currentSession: FocusSession?
    /// 计时器状态
    @Published var timerState: TimerState = .idle
    /// 计时器显示文本（如 "25:00"）
    @Published var timerDisplay: String = "25:00"
    /// 当前选中的任务
    @Published var selectedTask: Task?
    /// 当前活跃阶段
    @Published var activePhase: FocusPhase = .focus
    /// 当前是第几轮（第几个番茄钟）
    @Published var currentRoundIndex: Int = 1

    // MARK: - UI State (for test/compatibility)

    @Published var showCompletionAnimation = false
    @Published var errorMessage: String?
    @Published var showAchievementAlert = false
    @Published var todayCompletedCount = 0
    @Published var todayTotalDuration: TimeInterval = 0
    @Published var isWhiteNoiseOn = false

    // MARK: - Private State

    private var cancellables = Set<AnyCancellable>()
    private var durationForPhase: TimeInterval = AppConstants.defaultFocusDuration

    // MARK: - 根据阶段获取时长

    private func duration(for phase: FocusPhase) -> TimeInterval {
        switch phase {
        case .focus:
            return UserDefaults.standard.double(forKey: "focusDuration").nonZeroElse(AppConstants.defaultFocusDuration)
        case .shortBreak:
            return UserDefaults.standard.double(forKey: "shortBreakDuration").nonZeroElse(AppConstants.defaultShortBreakDuration)
        case .longBreak:
            return UserDefaults.standard.double(forKey: "longBreakDuration").nonZeroElse(AppConstants.defaultLongBreakDuration)
        }
    }

    // MARK: - Init

    init(
        focusService: FocusServiceProtocol,
        timerManager: TimerManager,
        notificationService: NotificationServiceProtocol,
        appBlockerService: AppBlockerServiceProtocol,
        audioService: AudioServiceProtocol,
        achievementService: AchievementServiceProtocol,
        taskService: TaskServiceProtocol
    ) {
        self.focusService = focusService
        self.timerManager = timerManager
        self.notificationService = notificationService
        self.appBlockerService = appBlockerService
        self.audioService = audioService
        self.achievementService = achievementService
        self.taskService = taskService

        // 观察 TimerManager 的状态变化
        timerManager.$timerState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.timerState = state
                if state == .finished {
                    self?.handleTimerFinished()
                }
            }
            .store(in: &cancellables)

        // 格式化剩余时间为显示文本
        timerManager.$timeRemaining
            .receive(on: DispatchQueue.main)
            .map { timeInterval in
                Self.formatTime(timeInterval)
            }
            .sink { [weak self] display in
                self?.timerDisplay = display
            }
            .store(in: &cancellables)

        // 检查是否有未完成的会话
        if let runningSession = focusService.getCurrentSession() {
            self.currentSession = runningSession
            self.activePhase = FocusPhase(rawValue: runningSession.phase) ?? .focus
            self.currentRoundIndex = Int(runningSession.roundIndex)
            self.timerState = .running
        }
    }

    // MARK: - Public Methods

    /// 开始专注（从指定阶段开始）
    func startFocus(phase: FocusPhase) {
        guard timerState != .running else { return }

        activePhase = phase
        durationForPhase = duration(for: phase)

        // 创建专注会话
        let session = focusService.startFocusSession(
            task: selectedTask,
            plannedDuration: durationForPhase,
            phase: phase,
            roundIndex: Int16(currentRoundIndex)
        )
        currentSession = session

        // 启动计时器
        timerManager.start(duration: durationForPhase)
        timerState = .running

        // 调度专注结束通知
        notificationService.scheduleSessionEndNotification(
            sessionId: session.id ?? UUID(),
            title: "专注完成",
            timeInterval: durationForPhase
        )

        // 启动应用屏蔽
        appBlockerService.startBlocking()

        // 播放开始音效
        audioService.playStartSound()
    }

    /// 暂停专注
    func pauseFocus() {
        timerManager.pause()
        timerState = timerManager.timerState
    }

    /// 恢复专注
    func resumeFocus() {
        timerManager.resume()
        timerState = timerManager.timerState
    }

    /// 跳过当前阶段
    func skipPhase() {
        guard let session = currentSession else { return }

        // 中断当前会话
        focusService.interruptSession(session)
        timerManager.stop()
        appBlockerService.stopBlocking()

        currentSession = nil
        timerState = .idle
        timerDisplay = Self.formatTime(duration(for: activePhase))

        // 完成当前番茄钟计数仍然增加（算作完成了一个番茄周期）
        // 但如果跳过的不是 focus 阶段，则不增加轮次
        if activePhase == .focus {
            currentRoundIndex += 1
        }

        // 播放提示音
        audioService.playAlarmSound()
    }

    /// 放弃当前会话
    func abandonSession() {
        guard let session = currentSession else { return }

        focusService.abandonSession(session)
        timerManager.stop()
        appBlockerService.stopBlocking()

        // 取消待处理的通知
        if let sessionId = session.id {
            notificationService.cancelNotification(withIdentifier: sessionId.uuidString)
        }

        currentSession = nil
        timerState = .idle
        timerDisplay = Self.formatTime(duration(for: activePhase))

        audioService.playAlarmSound()
    }

    // MARK: - Private Methods

    /// 计时器结束时处理回调
    private func handleTimerFinished() {
        guard let session = currentSession else { return }

        // 完成会话
        focusService.completeSession(session)

        // 停止应用屏蔽
        appBlockerService.stopBlocking()

        // 播放完成音效
        audioService.playCompleteSound()

        // 取消待处理的通知
        if let sessionId = session.id {
            notificationService.cancelNotification(withIdentifier: sessionId.uuidString)
        }

        // 注意：任务 completedPomodoros 已在 focusService.completeSession() 中递增
        // 这里不再重复调用 taskService.incrementCompletedPomodoros，避免双重计数

        // 检查成就解锁
        achievementService.checkAndUnlockAchievements()

        // 如果是专注阶段完成，增加轮次
        if activePhase == .focus {
            currentRoundIndex += 1
        }

        currentSession = nil
        timerState = .idle
        showCompletionAnimation = true
    }

    // MARK: - Computed Properties

    var isRunning: Bool { timerState == .running }
    var isPaused: Bool { timerState == .paused }
    var currentPhase: FocusPhase { activePhase }
    var currentRound: Int { currentRoundIndex }
    var progress: Double { timerManager.progress }

    // MARK: - Additional Public Methods

    func selectTask(_ task: Task?) {
        selectedTask = task
    }

    func refreshTodayStats() {
        let sessions = focusService.fetchTodaysSessions()
        todayCompletedCount = sessions.filter { $0.status == SessionStatus.completed.rawValue }.count
        todayTotalDuration = sessions.filter { $0.status == SessionStatus.completed.rawValue }.reduce(0) { $0 + $1.actualDuration }
    }

    func toggleWhiteNoise() {
        audioService.toggleWhiteNoise()
        isWhiteNoiseOn = audioService.isWhiteNoisePlaying
    }

    // MARK: - Helpers

    /// 格式化 TimeInterval 为 "mm:ss" 格式
    private static func formatTime(_ timeInterval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(timeInterval))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - 辅助扩展

private extension Double {
    func nonZeroElse(_ fallback: Double) -> Double {
        return self > 0 ? self : fallback
    }
}

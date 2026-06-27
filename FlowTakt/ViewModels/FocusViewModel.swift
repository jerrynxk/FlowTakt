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

    // MARK: - Deinit

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Private: Database Reset

    @objc private func handleDatabaseWillReset() {
        // 立即清空已删除的 ManagedObject 引用
        currentSession = nil
        selectedTask = nil
    }

    @objc private func handleDatabaseDidReset() {
        // No persistent data to reload for current session state
    }
    private var durationForPhase: TimeInterval = AppConstants.defaultFocusDuration
    private var wasWhiteNoiseOnBeforePause = false

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

        // 监听数据库重置通知，立即清空旧 ManagedObject 引用防止崩溃
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDatabaseWillReset),
            name: .databaseWillReset,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDatabaseDidReset),
            name: .databaseDidReset,
            object: nil
        )

        // 检查是否有未完成的会话（只记录状态，延迟到 View 就绪后再恢复）
        if let runningSession = focusService.getCurrentSession() {
            self.currentSession = runningSession
            self.activePhase = FocusPhase(rawValue: runningSession.phase) ?? .focus
            self.currentRoundIndex = Int(runningSession.roundIndex)

            if Date().timeIntervalSince(runningSession.startTime) > runningSession.plannedDuration {
                needsRestore = .expired(session: runningSession)
            } else {
                needsRestore = .running(session: runningSession)
            }
        }
    }

    /// View 就绪后调用，恢复未完成的会话（执行 CoreData 写入和计时器启动）
    func restorePendingSessionIfNeeded() {
        guard let needsRestore else { return }
        self.needsRestore = nil

        switch needsRestore {
        case .running(let session):
            let elapsed = Date().timeIntervalSince(session.startTime)
            let remaining = max(0, session.plannedDuration - elapsed)
            if remaining > 0 {
                timerManager.start(duration: remaining)
                timerState = .running
                appBlockerService.startBlocking()
                if activePhase == .focus, !audioService.isWhiteNoisePlaying {
                    audioService.toggleWhiteNoise()
                    isWhiteNoiseOn = true
                }
            }
        case .expired(let session):
            focusService.completeSession(session)
            self.currentSession = nil
            self.timerState = .idle
        }
    }

    /// 未完成会话的恢复状态（init 中不执行 CoreData 写入，延迟处理）
    private var needsRestore: RestoreState?
    private enum RestoreState {
        case running(session: FocusSession)
        case expired(session: FocusSession)
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
            sessionId: session.id,
            title: L10n.shared.专注结束,
            timeInterval: durationForPhase
        )

        // 启动应用屏蔽
        appBlockerService.startBlocking()

        // 播放开始音效
        audioService.playStartSound()

        // 专注阶段自动开启白噪音（仅在未播放时）
        if phase == .focus, !audioService.isWhiteNoisePlaying {
            audioService.toggleWhiteNoise()
            isWhiteNoiseOn = true
        }
    }

    /// 暂停专注
    func pauseFocus() {
        timerManager.pause()
        timerState = timerManager.timerState

        if isWhiteNoiseOn {
            audioService.toggleWhiteNoise()
            isWhiteNoiseOn = false
            wasWhiteNoiseOnBeforePause = true
        }
    }

    /// 恢复专注
    func resumeFocus() {
        timerManager.resume()
        timerState = timerManager.timerState

        if wasWhiteNoiseOnBeforePause {
            audioService.toggleWhiteNoise()
            isWhiteNoiseOn = true
            wasWhiteNoiseOnBeforePause = false
        }
    }

    /// 跳过当前阶段
    /// 语义：用户主动结束当前阶段（不等待计时器结束）。
    /// 快进到下一阶段：完成当前会话 → 自动开始下一阶段计时
    /// - focus → break（第 4 轮后长休息，否则短休息），轮次 +1
    /// - break → focus，轮次不变
    func skipPhase() {
        guard timerState == .running || timerState == .paused else { return }

        // 1. 完成当前会话
        if let session = currentSession {
            focusService.completeSession(session)
            notificationService.cancelNotification(withIdentifier: session.id.uuidString)
        }

        timerManager.stop()
        appBlockerService.stopBlocking()
        currentSession = nil

        // 2. 确定下一阶段
        let previousPhase = activePhase
        if previousPhase == .focus {
            currentRoundIndex += 1
            let longBreakEvery = UserDefaults.standard.integer(forKey: "longBreakAfterRounds").nonZeroElse(AppConstants.longBreakAfterRounds)
            activePhase = (currentRoundIndex % longBreakEvery == 0) ? .longBreak : .shortBreak
        } else {
            activePhase = .focus
        }

        // 3. 自动开始下一阶段
        timerDisplay = Self.formatTime(duration(for: activePhase))
        audioService.playCompleteSound()

        // 检查成就
        if previousPhase == .focus {
            achievementService.checkAndUnlockAchievements()
        }

        // 延迟启动下一段，避免动画冲突
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.startFocus(phase: self?.activePhase ?? .focus)
        }
    }

    /// 放弃当前会话
    func abandonSession() {
        if let session = currentSession {
            focusService.abandonSession(session)
            notificationService.cancelNotification(withIdentifier: session.id.uuidString)
        }

        timerManager.stop()
        appBlockerService.stopBlocking()
        currentSession = nil
        timerState = .idle
        timerDisplay = Self.formatTime(duration(for: activePhase))
        currentRoundIndex = 1
        activePhase = .focus

        if isWhiteNoiseOn {
            audioService.toggleWhiteNoise()
            isWhiteNoiseOn = false
        }
        wasWhiteNoiseOnBeforePause = false
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
        notificationService.cancelNotification(withIdentifier: session.id.uuidString)

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
// nonZeroElse 已提取到 Extensions/Numeric+Extensions.swift

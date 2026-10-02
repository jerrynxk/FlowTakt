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
    private let speechService: SpeechServiceProtocol

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
    @Published var todayCompletedCount = 0
    @Published var todayTotalDuration: TimeInterval = 0
    @Published var isWhiteNoiseOn = false
    /// 当前选中的白噪音类型（跨启动持久化，与 AudioService 源保持一致）
    @Published var selectedWhiteNoiseType: WhiteNoiseType = {
        let raw = UserDefaults.standard.string(forKey: "whiteNoiseType") ?? WhiteNoiseType.white.rawValue
        return WhiteNoiseType(rawValue: raw) ?? .white
    }()

    // MARK: - Private State

    private var cancellables = Set<AnyCancellable>()
    /// 防止 skipPhase 重复触发（竞态条件保护）
    private var isSkipping = false
    /// 会话代际计数：startFocus / abandon / pause 递增；skipPhase 延迟闭包用 token 校验，
    /// 避免「跳过 → 延迟启动下一段」窗口内用户放弃/暂停后仍自动开始新会话
    private var sessionGeneration = 0

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
        taskService: TaskServiceProtocol,
        speechService: SpeechServiceProtocol
    ) {
        self.focusService = focusService
        self.timerManager = timerManager
        self.notificationService = notificationService
        self.appBlockerService = appBlockerService
        self.audioService = audioService
        self.achievementService = achievementService
        self.taskService = taskService
        self.speechService = speechService

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
                // 重新调度「专注结束」通知（App 重启后原通知可能已被清除）
                notificationService.scheduleSessionEndNotification(
                    sessionId: session.id,
                    title: session.task?.title ?? L10n.shared.无任务,
                    timeInterval: remaining
                )
                if activePhase == .focus, !audioService.isWhiteNoisePlaying {
                    audioService.toggleWhiteNoise()
                    isWhiteNoiseOn = true
                }
            } else {
                // 审查修复（2026-08-12）：剩余时间 ≤ 0 时走「过期完成」逻辑，
                // 否则 running 会话永久残留（currentSession 非 nil 但 timerState=.idle），每次启动重复走该分支
                focusService.completeSession(session, actualDuration: session.plannedDuration)
                self.currentSession = nil
                self.timerState = .idle
                self.timerDisplay = Self.formatTime(duration(for: activePhase))
                achievementService.checkAndUnlockAchievements()
            }
        case .expired(let session):
            focusService.completeSession(session, actualDuration: session.plannedDuration)
            self.currentSession = nil
            self.timerState = .idle
            // 与正常完成路径一致：过期恢复也检查成就解锁
            achievementService.checkAndUnlockAchievements()
        }
    }

    /// 未完成会话的恢复状态（init 中不执行 CoreData 写入，延迟处理）
    private var needsRestore: RestoreState?
    private enum RestoreState {
        case running(session: FocusSession)
        case expired(session: FocusSession)
    }

    // MARK: - Public Methods

    /// 开始专注（从指定阶段开始，使用设置中的默认时长）
    func startFocus(phase: FocusPhase) {
        startFocus(phase: phase, durationOverride: nil)
    }

    /// 开始专注（支持自定义时长预设，绕过 UserDefaults 读取）
    /// - Parameters:
    ///   - phase: 起始阶段
    ///   - durationOverride: 自定义时长（秒）；为 nil 时回退到设置默认时长
    func startFocus(phase: FocusPhase, durationOverride: TimeInterval?) {
        guard timerState != .running else { return }
        // 触觉反馈：开始专注
        HapticManager.shared.lightImpact()
        // 代际 +1：使任何挂起的 skipPhase 延迟闭包失效（用户手动开始 = 新的会话周期）
        sessionGeneration += 1

        activePhase = phase
        durationForPhase = durationOverride ?? duration(for: phase)
        showCompletionAnimation = false

        // 创建专注会话（FocusService 内部会调度「专注结束」通知）
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

        // 启动应用屏蔽
        appBlockerService.startBlocking()

        // 播放开始音效
        audioService.playStartSound()

        // 专注阶段自动开启白噪音（仅在未播放时）
        if phase == .focus, !audioService.isWhiteNoisePlaying {
            audioService.setWhiteNoiseType(selectedWhiteNoiseType)
            audioService.toggleWhiteNoise()
            isWhiteNoiseOn = true
        }
    }

    /// 暂停专注
    /// 暂停时同时取消「专注结束」通知，避免用户暂停后通知仍在后台计时、
    /// 到点后误弹出"专注已结束"（用户感知为"已停止却仍弹通知"）
    func pauseFocus() {
        // 审查修复（2026-08-12）：状态 guard 前置，避免 idle 时触发也震动（timerManager.pause 自带 guard）
        guard timerState == .running else { return }
        // 代际 +1：取消挂起的 skipPhase 延迟启动（暂停 = 终止当前阶段）
        sessionGeneration += 1
        // 触觉反馈：暂停
        HapticManager.shared.lightImpact()
        timerManager.pause()
        timerState = timerManager.timerState

        if let session = currentSession {
            notificationService.cancelNotification(withIdentifier: session.id.uuidString)
        }

        if isWhiteNoiseOn {
            audioService.toggleWhiteNoise()
            isWhiteNoiseOn = false
            wasWhiteNoiseOnBeforePause = true
        }
    }

    /// 恢复专注
    /// 恢复时按剩余时间重新调度「专注结束」通知
    func resumeFocus() {
        // 审查修复（2026-08-12）：状态 guard 前置，避免非暂停态触发也震动
        guard timerState == .paused else { return }
        // 触觉反馈：恢复
        HapticManager.shared.lightImpact()
        timerManager.resume()
        timerState = timerManager.timerState

        if let session = currentSession {
            let remaining = max(0, timerManager.timeRemaining)
            if remaining > 0 {
                notificationService.scheduleSessionEndNotification(
                    sessionId: session.id,
                    title: session.task?.title ?? L10n.shared.无任务,
                    timeInterval: remaining
                )
            }
        }

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
    /// 使用 isSkipping 标志防止竞态条件（快速连续点击导致重复 startFocus）
    func skipPhase() {
        guard timerState == .running || timerState == .paused else { return }
        guard !isSkipping else { return }
        isSkipping = true
        // 触觉反馈：跳阶段
        HapticManager.shared.lightImpact()

        // 1. 完成当前会话（实际专注时长扣除暂停时间，避免统计虚高）
        // 审查修复（2026-08-12）：暂停态跳过时 totalPausedDuration 只含已结算暂停段，
        // 需补扣当前暂停段（pauseDate 至今），否则 actualDuration 虚高
        if let session = currentSession {
            let paused = timerManager.totalPausedDuration + timerManager.currentPausedDuration
            let actualDuration = max(0, Date().timeIntervalSince(session.startTime) - paused)
            focusService.completeSession(session, actualDuration: actualDuration)
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
        let nextPhase = activePhase
        timerDisplay = Self.formatTime(duration(for: nextPhase))
        audioService.playCompleteSound()

        // 检查成就
        if previousPhase == .focus {
            achievementService.checkAndUnlockAchievements()
        }

        // 延迟启动下一段，使用 nextPhase 而非捕获 self?.activePhase（避免延迟期间 phase 被修改）；
        // 用 sessionGeneration token 校验：窗口内用户 abandon / pause / 手动 start 都会递增代际，
        // 此时不再自动开始下一段（否则"放弃后自己又开始了"）
        let gen = sessionGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            guard self.sessionGeneration == gen else {
                self.isSkipping = false
                return
            }
            self.startFocus(phase: nextPhase)
            self.isSkipping = false
        }
    }

    /// 放弃当前会话
    /// - Parameter reason: 中断原因（可选，用户在弹窗中选择或输入）
    func abandonSession(reason: String? = nil) {
        // 代际 +1：取消挂起的 skipPhase 延迟启动
        sessionGeneration += 1
        // 触觉反馈：放弃会话（中度，提示操作影响）
        HapticManager.shared.mediumImpact()
        if let session = currentSession {
            focusService.abandonSession(session, reason: reason)
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

    // MARK: - v1.3 UI 升级：显式 phase 切换 + 时长预设 chip

    /// 显式切换 phase（来自顶部 Segmented Control）
    /// 仅在空闲态直接生效；运行中由 View 层弹二次确认后调用
    /// - Parameter phase: 目标阶段（专注 / 短休 / 长休）
    func switchPhase(_ phase: FocusPhase) {
        // 空闲态：直接切，重置显示时长（触觉：轻量选择反馈）
        if timerState == .idle {
            HapticManager.shared.selectionFeedback()
            activePhase = phase
            timerDisplay = Self.formatTime(duration(for: phase))
            return
        }
        // 运行中或暂停态：放弃当前会话（abandonSession 自带 medium 反馈，避免连震），
        // 按新阶段重置（不立即 start，由用户再主动点主按钮）
        abandonSession()
        activePhase = phase
        timerDisplay = Self.formatTime(duration(for: phase))
    }

    /// 用户通过 chip 选择了新的专注时长（持续阶段）
    /// - Parameter duration: 新时长（秒）
    func applyFocusDuration(_ duration: TimeInterval) {
        // 写 UserDefaults（与 SettingsViewModel 用同一个 key 保持一致）
        UserDefaults.standard.set(duration, forKey: "focusDuration")
        // 空闲态立即更新显示时长
        if timerState == .idle, activePhase == .focus {
            timerDisplay = Self.formatTime(duration)
        }
    }

    /// 用户通过 chip 选择了新的短休时长
    func applyShortBreakDuration(_ duration: TimeInterval) {
        UserDefaults.standard.set(duration, forKey: "shortBreakDuration")
        if timerState == .idle, activePhase == .shortBreak {
            timerDisplay = Self.formatTime(duration)
        }
    }

    /// 用户通过 chip 选择了新的长休时长
    func applyLongBreakDuration(_ duration: TimeInterval) {
        UserDefaults.standard.set(duration, forKey: "longBreakDuration")
        if timerState == .idle, activePhase == .longBreak {
            timerDisplay = Self.formatTime(duration)
        }
    }

    /// 清除当前选中的任务
    func clearSelectedTask() {
        selectedTask = nil
    }

    // MARK: - Private Methods

    /// 计时器结束时处理回调
    private func handleTimerFinished() {
        guard let session = currentSession else { return }

        // 完成会话，传入实际经过时间（扣除暂停时长，避免统计虚高）
        let actualDuration = max(0, Date().timeIntervalSince(session.startTime) - timerManager.totalPausedDuration)
        focusService.completeSession(session, actualDuration: actualDuration)

        // 停止应用屏蔽
        appBlockerService.stopBlocking()

        // 播放完成音效
        audioService.playCompleteSound()

        // 触觉反馈：专注完成（成功通知）
        HapticManager.shared.focusComplete()

        // 取消待处理的通知
        notificationService.cancelNotification(withIdentifier: session.id.uuidString)

        // 审查修复（2026-08-12）：专注自然结束后关闭白噪音（与 abandon/pause 路径一致），
        // 避免白噪音持续播放到用户手动关闭
        if isWhiteNoiseOn {
            audioService.toggleWhiteNoise()
            isWhiteNoiseOn = false
        }
        wasWhiteNoiseOnBeforePause = false

        // 注意：任务 completedPomodoros 已在 focusService.completeSession() 中递增
        // 这里不再重复调用 taskService.incrementCompletedPomodoros，避免双重计数

        // 检查成就解锁
        achievementService.checkAndUnlockAchievements()

        // 如果是专注阶段完成：语音播报「第 X 个番茄完成」（使用递增前的轮次），随后增加轮次
        if activePhase == .focus {
            speechService.speak(L10n.shared.第X个番茄完成(currentRoundIndex))
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

    func toggleWhiteNoise() {
        audioService.toggleWhiteNoise()
        isWhiteNoiseOn = audioService.isWhiteNoisePlaying
    }

    /// 切换白噪音类型（持久化并实时应用到正在播放的音色）
    func setWhiteNoiseType(_ type: WhiteNoiseType) {
        selectedWhiteNoiseType = type
        UserDefaults.standard.set(type.rawValue, forKey: "whiteNoiseType")
        if isWhiteNoiseOn {
            audioService.setWhiteNoiseType(type)
        }
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

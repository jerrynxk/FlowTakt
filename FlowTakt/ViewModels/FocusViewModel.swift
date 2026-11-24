import Foundation
import Combine
import SwiftUI
import CoreData

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
    /// 完成瞬间的状态标记（当前无 View 消费，但单元测试以此断言完成路径；保留）
    @Published var showCompletionAnimation = false
    @Published var timerDisplay: String = "25:00"
    /// 当前选中的任务
    @Published var selectedTask: Task?
    /// 当前活跃阶段
    @Published var activePhase: FocusPhase = .focus
    /// 当前是第几轮（第几个番茄钟）
    @Published var currentRoundIndex: Int = 1

    // MARK: - UI State (for test/compatibility)

    @Published var isWhiteNoiseOn = false
    /// 当前选中的白噪音类型（跨启动持久化，与 AudioService 源保持一致）
    @Published var selectedWhiteNoiseType: WhiteNoiseType = {
        let raw = UserDefaults.standard.string(forKey: "whiteNoiseType") ?? WhiteNoiseType.white.rawValue
        return WhiteNoiseType(rawValue: raw) ?? .white
    }()

    /// 「专注开始时自动播放白噪音」偏好键（用户反馈 2026-11-19）。
    /// 与 SettingsViewModel 的同名 @AppStorage 共用此键 —— 两处判据必须同一个键，
    /// 否则设置页关掉、专注页仍自动播放。
    static let whiteNoiseAutoPlayKey = "whiteNoiseAutoPlay"

    /// 是否允许在专注开始时自动播放白噪音。默认 true（保持既有行为）；
    /// 用户在专注页手动关闭白噪音后会被记忆为 false，下次开始专注不再自动播放。
    /// 读 `object(forKey:)` 以区分「从未设置」（默认开）与「用户明确关闭」。
    private var autoPlayWhiteNoise: Bool {
        UserDefaults.standard.object(forKey: Self.whiteNoiseAutoPlayKey) as? Bool ?? true
    }

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
        // 修复（2026-10-14 审查 P1-6）：重置前必须停表。旧实现只清空引用，
        // timerManager 继续跑、timerState 仍为 .running → 之后点开始被
        // `guard timerState != .running` 静默拦截（旧计时器走完前一直无法开始），
        // 且旧会话的「专注结束」通知会残留误弹。
        if let session = currentSession {
            notificationService.cancelNotification(withIdentifier: session.id.uuidString)
        }
        // 修复（2026-10-15 通知乱弹）：currentSession 可能为 nil（会话已删除/跨设备同步删除），
        // 此时旧通知无从按 id 取消 —— 全量清理会话类待处理通知兜底。
        notificationService.cancelAllSessionNotifications()
        timerManager.stop()
        appBlockerService.stopBlocking()
        timerState = .idle
        timerDisplay = Self.formatTime(duration(for: activePhase))
        currentSession = nil
        selectedTask = nil
        if isWhiteNoiseOn {
            audioService.toggleWhiteNoise()
            isWhiteNoiseOn = false
        }
        wasWhiteNoiseOnBeforePause = false
        sessionGeneration += 1
        // 灵动岛：重置数据库时结束残留的 Live Activity（2026-10-14）
        FocusLiveActivity.end()
    }

    @objc private func handleDatabaseDidReset() {
        // No persistent data to reload for current session state
    }

    /// 会话记录已被删除时的本地状态清理（修复 2026-10-14 审查 P0-2 兜底）
    ///
    /// 触发场景：删除正在专注的任务（历史路径已由 `TaskService.deleteTask` 先解除关联）、
    /// CloudKit 同步从其它设备删除了该任务/会话。共用一条清理路径，绝不触碰已删对象。
    private func cleanUpDeletedSession() {
        timerManager.stop()
        appBlockerService.stopBlocking()
        currentSession = nil
        selectedTask = nil
        timerState = .idle
        timerDisplay = Self.formatTime(duration(for: activePhase))
        sessionGeneration += 1
        if isWhiteNoiseOn {
            audioService.toggleWhiteNoise()
            isWhiteNoiseOn = false
        }
        FocusLiveActivity.end()
    }

    /// 会话是否仍有效。所有触碰 currentSession 的入口都要先过这一关。
    ///
    /// 判据只看 `isDeleted`（级联删除的真实症状）。**不能**把 `managedObjectContext == nil`
    /// 也算作失效：单元测试构造的会话本就无上下文，误判会让暂停/恢复提前 return，
    ///连带跳过 `sessionGeneration += 1`，导致 skipPhase 的延迟启动未被取消。
    private var hasLiveSession: Bool {
        currentSession?.isDeleted != true
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

            // 修复（2026-10-14 审查 P1-9）：用**持久化的净专注秒数**推算剩余，而非挂钟时间。
            // 旧实现 `Date() - startTime > plannedDuration → expired` 会把「暂停后进程被回收」
            // 的会话误判为已超时完成（记成完整番茄 + 积分 + 任务番茄数 +1）。
            let active = focusService.activeElapsedSeconds(for: runningSession)
            let remaining = runningSession.plannedDuration - active
            if runningSession.status == SessionStatus.paused.rawValue {
                needsRestore = .paused(session: runningSession, remaining: max(0, remaining))
            } else if remaining > 0 {
                needsRestore = .running(session: runningSession)
            } else {
                needsRestore = .expired(session: runningSession)
            }
        }
    }

    /// View 就绪后调用，恢复未完成的会话（执行 CoreData 写入和计时器启动）
    func restorePendingSessionIfNeeded() {
        guard let needsRestore else { return }
        self.needsRestore = nil

        switch needsRestore {
        case .running(let session):
            let remaining = max(0, session.plannedDuration - focusService.activeElapsedSeconds(for: session))
            if remaining > 0 {
                timerManager.start(duration: remaining)
                timerState = .running
                appBlockerService.startBlocking()
                // 重新调度「专注结束」通知（App 重启后原通知可能已被清除）
                // 修复（2026-10-15 通知乱弹）：scheduleSessionEndNotification 内部已先
                // 清理所有会话类残留通知，此处只需按新的剩余时间重新调度一条。
                notificationService.scheduleSessionEndNotification(
                    sessionId: session.id,
                    title: session.task?.title ?? L10n.shared.无任务,
                    timeInterval: remaining
                )
                if activePhase == .focus, autoPlayWhiteNoise, !audioService.isWhiteNoisePlaying {
                    audioService.toggleWhiteNoise()
                    isWhiteNoiseOn = true
                }
                // 灵动岛：冷启动恢复会话时同步（活动仍在则更新，已被系统清理则重建，2026-10-14）
                // 复审修复（2026-10-14 P1-B）：会话含暂停时，原始 startTime+plannedDuration
                // 可能已是过去时刻 → 灵动岛/锁屏显示 00:00 且进度条 100%、staleDate 立即过期。
                // 改为「现在 → 现在+剩余」，与 resumeFocus 同构；totalDuration 仍传计划总时长，
                // 保证进度比例正确。
                FocusLiveActivity.startOrUpdate(
                    phaseRaw: activePhase.rawValue,
                    startDate: Date(),
                    endDate: Date().addingTimeInterval(remaining),
                    totalDuration: session.plannedDuration,
                    taskTitle: session.task?.title
                )
            } else {
                // 审查修复（2026-08-12）：剩余时间 ≤ 0 时走「过期完成」逻辑，
                // 否则 running 会话永久残留（currentSession 非 nil 但 timerState=.idle），每次启动重复走该分支
                focusService.completeSession(session, actualDuration: session.plannedDuration)
                self.currentSession = nil
                self.timerState = .idle
                self.timerDisplay = Self.formatTime(duration(for: activePhase))
                achievementService.checkAndUnlockAchievements()
                // 灵动岛：会话已过期的残留活动一并结束
                FocusLiveActivity.end()
            }
        case .expired(let session):
            focusService.completeSession(session, actualDuration: session.plannedDuration)
            self.currentSession = nil
            self.timerState = .idle
            // 与正常完成路径一致：过期恢复也检查成就解锁
            achievementService.checkAndUnlockAchievements()
            // 灵动岛：过期会话的残留活动一并结束
            FocusLiveActivity.end()
        case .paused(let session, let remaining):
            // 修复（2026-10-14 审查 P1-9）：恢复为「暂停中」而不是自动续跑 ——
            // 用户明确按了暂停，进程重启不应替他继续；剩余时间沿用暂停时冻结的值。
            timerManager.start(duration: max(1, remaining))
            timerManager.pause()
            self.timerState = .paused
            self.timerDisplay = Self.formatTime(remaining)
            // 修复（2026-10-15 通知乱弹）：进程被杀前若处于 running，已调度的「专注结束」
            // 通知仍留在 iOS pending 队列里（iOS 不随进程消亡）。恢复为暂停态时若不清掉，
            // 用户明明已暂停却仍会收到"专注已完成"——正是反馈的乱弹来源。
            notificationService.cancelAllSessionNotifications()
            // 暂停中不启动屏蔽
            FocusLiveActivity.startOrUpdatePaused(
                phaseRaw: activePhase.rawValue,
                remaining: remaining,
                totalDuration: session.plannedDuration,
                taskTitle: session.task?.title
            )
        }
    }

    /// 外部控制入口的最小状态对齐（2026-10-15）。
    ///
    /// 背景 / 冷启动执行 Live Activity 按钮（LiveActivityIntent 由系统路由到 App 进程）时，
    /// `FocusView` 未上屏 → `restorePendingSessionIfNeeded()` 不会执行 →
    /// `timerState` 停留 `.idle`（timer 未启动），使 `pauseFocus` / `resumeFocus` 的
    /// 状态 guard 静默吞掉点击 —— 用户表现为「按钮点了没反应 / 反应慢」。
    ///
    /// 本方法在控制动作前把 `needsRestore`（init 已计算，判据与前台恢复**同源**）消费掉，
    /// **仅**恢复计时核心（timer + timerState），不执行白噪音 / 通知重排 / 灵动岛重建等
    /// 「前台恢复体验」副作用 —— 那些由控制动作本身（pause / resume / stop）覆盖：
    /// - pause：落库暂停、更新灵动岛为暂停态、取消结束通知、停白噪音
    /// - resume：重新计时、更新灵动岛、重排通知
    /// - stop：abandon 落库、结束活动、清理全部状态
    ///
    /// 判据收口：与 `restorePendingSessionIfNeeded` 共享同一 `needsRestore` 数据源，
    /// 二者先到先消费、后到者跳过（不会重复启动 timer）。
    func ensureOperableStateForExternalControl() {
        // 已处于可操作状态（前台运行 / 已恢复）→ 无需对齐
        guard timerState == .idle, let state = needsRestore else { return }
        needsRestore = nil

        switch state {
        case .running(let session):
            let remaining = max(0, session.plannedDuration - focusService.activeElapsedSeconds(for: session))
            if remaining > 0 {
                timerManager.start(duration: remaining)
                timerState = .running
            } else {
                // 过期：与前台恢复逻辑同判据 —— 完成落库并清理残留活动
                focusService.completeSession(session, actualDuration: session.plannedDuration)
                currentSession = nil
                timerState = .idle
                FocusLiveActivity.end()
            }
        case .paused(_, let remaining):
            // currentSession / activePhase 已由 init 对齐；此处仅把计时核心恢复为暂停态
            // （与 restorePendingSessionIfNeeded 的 paused 分支同型）
            timerManager.start(duration: max(1, remaining))
            timerManager.pause()
            timerState = .paused
        case .expired(let session):
            focusService.completeSession(session, actualDuration: session.plannedDuration)
            currentSession = nil
            timerState = .idle
            FocusLiveActivity.end()
        }
    }

    /// 未完成会话的恢复状态（init 中不执行 CoreData 写入，延迟处理）
    private var needsRestore: RestoreState?
    private enum RestoreState {
        case running(session: FocusSession)
        /// 暂停中恢复（2026-10-14 审查 P1-9）：剩余时间在暂停时刻已冻结
        case paused(session: FocusSession, remaining: TimeInterval)
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

        // 灵动岛 / 锁屏 Live Activity：开始或更新（2026-10-14）
        FocusLiveActivity.startOrUpdate(
            phaseRaw: phase.rawValue,
            startDate: Date(),
            endDate: Date().addingTimeInterval(durationForPhase),
            totalDuration: durationForPhase,
            taskTitle: selectedTask?.title
        )

        // 启动应用屏蔽
        appBlockerService.startBlocking()

        // 播放开始音效
        audioService.playStartSound()

        // 专注阶段自动开启白噪音（仅在未播放时，且尊重用户「不再自动播放」的选择）
        if phase == .focus, autoPlayWhiteNoise, !audioService.isWhiteNoisePlaying {
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
        guard hasLiveSession else {
            if currentSession != nil { cleanUpDeletedSession() }
            return
        }
        // 代际 +1：取消挂起的 skipPhase 延迟启动（暂停 = 终止当前阶段）
        sessionGeneration += 1
        // 触觉反馈：暂停
        HapticManager.shared.lightImpact()
        timerManager.pause()
        timerState = timerManager.timerState

        // 修复（2026-10-14 审查 P1-9）：暂停状态落库（状态 + 净专注秒 + 暂停时刻），
        // 否则「暂停后进程被回收」会被按挂钟时间误判为超时完成。
        if let session = currentSession {
            // 复审修复：暂停落库的值也必须来自同一真值源（跨进程后 TimerManager 已无历史）
            focusService.pauseSession(session, activeSeconds: focusService.activeElapsedSeconds(for: session))
        }

        // 灵动岛：切换为「已暂停」静态展示（2026-10-14）
        FocusLiveActivity.updatePaused(
            phaseRaw: activePhase.rawValue,
            remaining: timerManager.timeRemaining,
            totalDuration: currentSession?.plannedDuration ?? 0,
            taskTitle: selectedTask?.title
        )

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
        guard hasLiveSession else {
            if currentSession != nil { cleanUpDeletedSession() }
            return
        }
        // 触觉反馈：恢复
        HapticManager.shared.lightImpact()
        timerManager.resume()
        timerState = timerManager.timerState
        // 恢复落库：updatedAt 作为本段计时起点（P1-9）
        if let session = currentSession {
            focusService.resumeSession(session)
        }

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

        // 灵动岛：恢复倒计时——剩余 > 0 时以「现在 + 剩余」重建结束时间续跑（2026-10-14）
        let liveRemaining = max(0, timerManager.timeRemaining)
        if liveRemaining > 0 {
            FocusLiveActivity.startOrUpdate(
                phaseRaw: activePhase.rawValue,
                startDate: Date(),
                endDate: Date().addingTimeInterval(liveRemaining),
                totalDuration: currentSession?.plannedDuration ?? liveRemaining,
                taskTitle: selectedTask?.title
            )
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
        guard hasLiveSession else {
            if currentSession != nil { cleanUpDeletedSession() }
            return
        }
        guard !isSkipping else { return }
        isSkipping = true
        // 触觉反馈：跳阶段
        HapticManager.shared.lightImpact()

        // 1. 完成当前会话（实际专注时长扣除暂停时间，避免统计虚高）
        // 审查修复（2026-08-12）：暂停态跳过时 totalPausedDuration 只含已结算暂停段，
        // 需补扣当前暂停段（pauseDate 至今），否则 actualDuration 虚高
        if let session = currentSession {
            // 同上：统一走持久化推导的净专注秒数
            let actualDuration = focusService.activeElapsedSeconds(for: session)
            focusService.completeSession(session, actualDuration: actualDuration)
            notificationService.cancelNotification(withIdentifier: session.id.uuidString)
        }

        timerManager.stop()
        appBlockerService.stopBlocking()
        currentSession = nil

        // 2. 确定下一阶段（轮次规则收口到 nextPhaseAfterCompletion，与自然完成路径一致）
        let previousPhase = activePhase
        if previousPhase == .focus {
            currentRoundIndex += 1
            activePhase = nextPhaseAfterCompletion(.focus)
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
        // 自动开始受设置约束（修复 P2）：关闭「自动开始休息/专注」时，跳过只切换阶段不启动，
        // 否则设置项形同虚设（本轮审查 P1-15 已让自然完成路径读设置，跳过路径此前不读）。
        guard autoStartEnabled(forPhase: previousPhase) else {
            isSkipping = false
            return
        }
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
        // 修复（P0-2 兜底）：会话可能已被删除，此时不得触碰其属性
        if let session = currentSession, hasLiveSession {
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

        // 灵动岛：结束活动（放弃 / 切阶段路径均经此处，2026-10-14）
        FocusLiveActivity.end()

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
            // 修复（2026-10-14 P2）：用户主动改阶段应使挂起的「自动开始下一阶段」失效
            sessionGeneration += 1
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

    // MARK: - Private Methods

    /// 计时器结束时处理回调
    private func handleTimerFinished() {
        guard hasLiveSession else {
            if currentSession != nil { cleanUpDeletedSession() }
            return
        }
        guard let session = currentSession else { return }

        // 完成会话，传入实际净专注时长（扣除暂停时间，避免统计虚高）
        // 复审修复（2026-10-14 P0）：唯一真值来源改为 focusService.activeElapsedSeconds。
        // 原用 TimerManager 内存累计（totalPausedDuration）在跨进程恢复后已被清零，
        // 与持久化的 startTime 脱钩 → 时长虚高并污染 actualDuration。
        let actualDuration = focusService.activeElapsedSeconds(for: session)
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

        // 修复（2026-10-14 审查 P1-15）：「自动开始休息 / 自动开始专注」两个开关此前
        // 全项目**无任何消费方**（开关可点但什么都不发生 = 摆设）。
        // 现按设置实现：完成当前阶段后自动启动下一阶段（延迟 1.2s 让完成动画可见；
        // 沿用 sessionGeneration 代际校验，用户中途放弃/暂停则不自动启动）。
        if shouldAutoStartNextPhase {
            let finishedPhase = activePhase
            let nextPhase = nextPhaseAfterCompletion(finishedPhase)
            let gen = sessionGeneration
            // 马上要切到下一阶段，不再保留 30s 的「已完成」展示
            FocusLiveActivity.end()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                guard let self, self.sessionGeneration == gen else { return }
                self.startFocus(phase: nextPhase)
            }
        } else {
            // 灵动岛：保留「已完成」展示 30s 后自动消失（2026-10-14）
            FocusLiveActivity.endCompleted(
                phaseRaw: activePhase.rawValue,
                taskTitle: selectedTask?.title
            )
        }
    }

    /// 是否自动开始下一阶段（读设置页两个开关；默认值与设置页一致：自动开始休息=开、自动开始专注=关）
    private var shouldAutoStartNextPhase: Bool {
        autoStartEnabled(forPhase: activePhase)
    }

    /// 某阶段结束后是否应自动开始（判据收口：自然完成与跳过两条路径共用）
    private func autoStartEnabled(forPhase finishedPhase: FocusPhase) -> Bool {
        let isFocus = finishedPhase == .focus
        let key = isFocus ? "autoStartBreaks" : "autoStartFocus"
        return UserDefaults.standard.object(forKey: key) as? Bool ?? isFocus
    }

    /// 完成某阶段后的下一阶段（轮次规则与 skipPhase 共用本函数，判据收口在一处）
    ///
    /// 修复（2026-10-14 P2）：原判据 `currentRoundIndex % every == 0` 让「每 4 轮长休息」
    /// 实际在**第 3 个番茄之后**触发（轮次从 1 起算）。改为先自减再取模。
    private func nextPhaseAfterCompletion(_ finishedPhase: FocusPhase) -> FocusPhase {
        guard finishedPhase == .focus else { return .focus }
        let every = UserDefaults.standard.integer(forKey: "longBreakAfterRounds")
            .nonZeroElse(AppConstants.longBreakAfterRounds)
        return ((currentRoundIndex - 1) % every == 0) ? .longBreak : .shortBreak
    }

    /// 恢复轮次计数（供「仅改时长、不打断轮次进度」的场景使用）
    func restoreRoundIndex(_ value: Int) {
        currentRoundIndex = max(1, value)
    }

    /// 清除已选择的任务（取消关联）
    /// 注：审查时曾被误判为死代码删除，实际 FocusViewModelTests 有用例调用 —— 已恢复。
    func clearSelectedTask() {
        selectedTask = nil
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

    /// 白噪音功能开关（偏好）：决定「点击开始专注时是否自动播放白噪音」。
    /// 2026-11-22 语义调整为纯开关——不直接控制音频播放：
    /// 未开始专注时打开它不会出声；真正播放由 startFocus / 恢复路径依据此偏好触发。
    /// 与 SettingsViewModel 的同名 @AppStorage 共用 whiteNoiseAutoPlayKey 键，两处始终同步。
    var isWhiteNoiseEnabled: Bool {
        get { autoPlayWhiteNoise }
        set { UserDefaults.standard.set(newValue, forKey: Self.whiteNoiseAutoPlayKey) }
    }

    func toggleWhiteNoise() {
        // 2026-11-22：开关只切换偏好，不再调用 audioService（原实现开关即播放/停止，
        // 导致未开始专注时打开开关就出声）。
        // - 运行时状态 isWhiteNoiseOn（音频是否正在播放）不在此处改动，
        //   由 startFocus / pause / resume / abandon / finish 等生命周期路径维护。
        // - 真正播放只发生在「开始专注」时：startFocus / restorePendingSessionIfNeeded
        //   依据 isWhiteNoiseEnabled（= autoPlayWhiteNoise 偏好）决定是否播放。
        isWhiteNoiseEnabled.toggle()
        // isWhiteNoiseEnabled 是读 UserDefaults 的计算属性（非 @Published），写偏好本身
        // 不会通知 SwiftUI → 菜单里的圆圈/图标/文字颜色点完不更新（2026-11-22 bug）。
        // 手动发送 objectWillChange，让订阅视图重绘并重新读取计算属性拿到新值；
        // 同时保留「每次都读 UserDefaults」特性，使设置页 @AppStorage 改动也能同步过来。
        objectWillChange.send()
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

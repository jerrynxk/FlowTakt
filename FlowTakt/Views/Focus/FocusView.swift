import SwiftUI

// MARK: - 专注主视图

struct FocusView: View {
    @EnvironmentObject var focusViewModel: FocusViewModel
    @EnvironmentObject var taskViewModel: TaskViewModel
    @EnvironmentObject var statsViewModel: StatsViewModel
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @EnvironmentObject var l10n: L10n

    // MARK: - 进度计算

    /// 当前阶段的总时长
    private var totalDuration: TimeInterval {
        switch focusViewModel.activePhase {
        case .focus:
            return settingsViewModel.focusDuration
        case .shortBreak:
            return settingsViewModel.shortBreakDuration
        case .longBreak:
            return settingsViewModel.longBreakDuration
        }
    }

    /// 精确的进度值（0.0 ~ 1.0），直接使用 TimerManager 的 progress，避免字符串解析
    private var progressValue: Double {
        switch focusViewModel.timerState {
        case .idle:
            return 0
        case .finished:
            return 1
        case .running, .paused:
            return min(1, max(0, focusViewModel.progress))
        }
    }

    /// 长休息前的轮次阈值
    private var longBreakAfterRounds: Int {
        settingsViewModel.longBreakAfterRounds
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            let isCompact = geometry.size.height < 700
            ScrollView(showsIndicators: false) {
                VStack(spacing: isCompact ? 12 : 24) {
                    Spacer().frame(height: isCompact ? 8 : 20)

                    // 阶段标识
                    FocusPhaseBadge()
                        .environmentObject(focusViewModel)

                    // 圆形计时器
                    CircularTimerView(progress: progressValue)
                        .environmentObject(focusViewModel)
                        .frame(
                            width: isCompact
                                ? min(geometry.size.width - 40, 220)
                                : min(geometry.size.width - 80, 300),
                            height: isCompact
                                ? min(geometry.size.width - 40, 220)
                                : min(geometry.size.width - 80, 300)
                        )

                    // 轮次进度
                    roundProgressView

                    // 任务关联选择器
                    TaskBindingView()
                        .environmentObject(focusViewModel)
                        .environmentObject(taskViewModel)

                    // 进度条
                    ProgressBarView(progress: progressValue)
                        .environmentObject(focusViewModel)
                        .padding(.horizontal, 40)

                    // 开始/暂停按钮
                    StartButtonView()
                        .environmentObject(focusViewModel)

                    // 白噪音开关
                    whiteNoiseToggle

                    // 今日迷你统计
                    TodayMiniStatsView()
                        .environmentObject(statsViewModel)
                        .padding(.horizontal, 40)
                        .padding(.bottom, 32)
                }
                .frame(minHeight: geometry.size.height)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color.appBackground.ignoresSafeArea())
        .task {
            focusViewModel.restorePendingSessionIfNeeded()
        }
    }

    // MARK: - 轮次进度

    private var roundProgressView: some View {
        HStack(spacing: 8) {
            // 使用非负取模，避免 currentRoundIndex 为 0 或异常值时产生负数
            let completedInCycle = ((focusViewModel.currentRoundIndex - 1) % longBreakAfterRounds + longBreakAfterRounds) % longBreakAfterRounds
            ForEach(0..<longBreakAfterRounds, id: \.self) { index in
                Circle()
                    .fill(index < completedInCycle
                          ? Color.forPhase(focusViewModel.activePhase)
                          : Color(.systemGray4))
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
            }

            Text(L10n.shared.round(focusViewModel.currentRoundIndex))
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 4)
                .accessibilityLabel(L10n.shared.round(focusViewModel.currentRoundIndex))
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - 白噪音开关

    private var whiteNoiseToggle: some View {
        Button {
            focusViewModel.toggleWhiteNoise()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: focusViewModel.isWhiteNoiseOn ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.system(size: 14))
                Text(focusViewModel.isWhiteNoiseOn ? L10n.shared.白噪音开 : L10n.shared.白噪音关)
                    .font(.subheadline)
            }
            .foregroundColor(focusViewModel.isWhiteNoiseOn ? .focusRed : .secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(focusViewModel.isWhiteNoiseOn
                          ? Color.focusRed.opacity(0.1)
                          : Color(.systemGray5))
            )
        }
        .accessibilityLabel(focusViewModel.isWhiteNoiseOn ? L10n.shared.白噪音开 : L10n.shared.白噪音关)
    }
}

#if DEBUG
struct FocusView_Previews: PreviewProvider {
    static var previews: some View {
        FocusView()
            .environmentObject(FocusViewModel(
                focusService: FocusService(
                    persistenceController: PersistenceController.shared,
                    notificationService: NotificationService()
                ),
                timerManager: TimerManager(),
                notificationService: NotificationService(),
                appBlockerService: AppBlockerService(),
                audioService: AudioService(),
                achievementService: AchievementService(
                    persistenceController: PersistenceController.shared,
                    focusService: FocusService(
                        persistenceController: PersistenceController.shared,
                        notificationService: NotificationService()
                    )
                ),
                taskService: TaskService(persistenceController: PersistenceController.shared)
            ))
            .environmentObject(SettingsViewModel(syncService: MockSyncService()))
    }
}
#endif

import SwiftUI

// MARK: - 专注主视图

struct FocusView: View {
    @EnvironmentObject var focusViewModel: FocusViewModel
    @EnvironmentObject var taskViewModel: TaskViewModel
    @EnvironmentObject var statsViewModel: StatsViewModel
    @EnvironmentObject var settingsViewModel: SettingsViewModel

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

    /// 精确的进度值（0.0 ~ 1.0）
    private var progressValue: Double {
        switch focusViewModel.timerState {
        case .idle:
            return 0
        case .finished:
            return 1
        case .running, .paused:
            let components = focusViewModel.timerDisplay.split(separator: ":")
            guard components.count == 2,
                  let minutes = Double(components[0]),
                  let seconds = Double(components[1]) else {
                return 0
            }
            let remaining = minutes * 60 + seconds
            guard totalDuration > 0 else { return 0 }
            return min(1, max(0, 1 - (remaining / totalDuration)))
        }
    }

    /// 长休息前的轮次阈值
    private var longBreakAfterRounds: Int {
        settingsViewModel.longBreakAfterRounds
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    Spacer().frame(height: 20)

                    // 阶段标识
                    FocusPhaseBadge()
                        .environmentObject(focusViewModel)

                    // 圆形计时器
                    CircularTimerView(progress: progressValue)
                        .environmentObject(focusViewModel)
                        .frame(width: min(geometry.size.width - 80, 300),
                               height: min(geometry.size.width - 80, 300))

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
                        .padding(.top, 8)

                    Spacer(minLength: 20)

                    // 今日迷你统计
                    TodayMiniStatsView()
                        .environmentObject(statsViewModel)
                        .padding(.horizontal, 40)
                        .padding(.bottom, 16)
                }
                .frame(minHeight: geometry.size.height)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color.appBackground.ignoresSafeArea())
    }

    // MARK: - 轮次进度

    private var roundProgressView: some View {
        HStack(spacing: 8) {
            ForEach(0..<longBreakAfterRounds, id: \.self) { index in
                Circle()
                    .fill(index < (focusViewModel.currentRoundIndex - 1) % longBreakAfterRounds
                          ? Color.forPhase(focusViewModel.activePhase)
                          : Color(.systemGray4))
                    .frame(width: 10, height: 10)
            }

            Text("第 \(focusViewModel.currentRoundIndex) 轮")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 4)
        }
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
            .environmentObject(SettingsViewModel())
    }
}
#endif

import SwiftUI

// MARK: - 圆形计时器

struct CircularTimerView: View {
    @EnvironmentObject var focusViewModel: FocusViewModel

    let progress: Double

    private let lineWidth: CGFloat = 10

    var body: some View {
        ZStack {
            // 背景圆环
            Circle()
                .stroke(Color(.systemGray5), lineWidth: lineWidth)

            // 进度圆环
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    Color.forPhase(focusViewModel.activePhase),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.1), value: progress)

            // 时间显示
            VStack(spacing: 4) {
                Text(focusViewModel.timerDisplay)
                    .font(.system(size: 56, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
                    .contentTransition(.numericText())
                    .animation(.linear(duration: 0.1), value: focusViewModel.timerDisplay)

                Text(focusViewModel.timerState == .running ? "进行中"
                     : focusViewModel.timerState == .paused ? "已暂停"
                     : focusViewModel.timerState == .finished ? "已完成"
                     : "准备就绪")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

#if DEBUG
struct CircularTimerView_Previews: PreviewProvider {
    static var previews: some View {
        CircularTimerView(progress: 0.3)
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
            .frame(width: 250, height: 250)
            .padding()
    }
}
#endif

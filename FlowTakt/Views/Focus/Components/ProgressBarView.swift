import SwiftUI

// MARK: - 进度条

struct ProgressBarView: View {
    @EnvironmentObject var focusViewModel: FocusViewModel

    let progress: Double

    private var phaseColor: Color {
        Color.forPhase(focusViewModel.activePhase)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // 背景轨道
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(.systemGray5))
                    .frame(height: 6)

                // 进度填充
                RoundedRectangle(cornerRadius: 3)
                    .fill(phaseColor)
                    .frame(width: geometry.size.width * CGFloat(progress), height: 6)
                    .animation(.linear(duration: 0.1), value: progress)
            }
        }
        .frame(height: 6)
    }
}

#if DEBUG
struct ProgressBarView_Previews: PreviewProvider {
    static var previews: some View {
        ProgressBarView(progress: 0.45)
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
            .padding(.horizontal, 40)
    }
}
#endif

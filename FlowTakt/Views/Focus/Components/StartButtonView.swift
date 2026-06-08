import SwiftUI

// MARK: - 开始/暂停按钮

struct StartButtonView: View {
    @EnvironmentObject var focusViewModel: FocusViewModel

    private var phaseColor: Color {
        Color.forPhase(focusViewModel.activePhase)
    }

    var body: some View {
        HStack(spacing: 24) {
            // 跳过按钮（仅在计时运行或暂停时显示）
            if focusViewModel.timerState == .running || focusViewModel.timerState == .paused {
                Button(action: {
                    focusViewModel.skipPhase()
                }) {
                    Image(systemName: "forward.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                        .frame(width: 52, height: 52)
                        .background(Color(.systemGray6))
                        .clipShape(Circle())
                }
                .transition(.opacity.combined(with: .scale))
            }

            // 主按钮
            Button(action: mainAction) {
                Image(systemName: mainIcon)
                    .font(.title)
                    .foregroundColor(.white)
                    .frame(width: 72, height: 72)
                    .background(phaseColor)
                    .clipShape(Circle())
                    .shadow(color: phaseColor.opacity(0.4), radius: 8, x: 0, y: 4)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: focusViewModel.timerState)
    }

    // MARK: - Helpers

    private var mainIcon: String {
        switch focusViewModel.timerState {
        case .idle:
            return "play.fill"
        case .running:
            return "pause.fill"
        case .paused:
            return "play.fill"
        case .finished:
            return "arrow.counterclockwise"
        }
    }

    private func mainAction() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            switch focusViewModel.timerState {
            case .idle:
                focusViewModel.startFocus(phase: .focus)
            case .running:
                focusViewModel.pauseFocus()
            case .paused:
                focusViewModel.resumeFocus()
            case .finished:
                focusViewModel.startFocus(phase: .focus)
            }
        }
    }
}

#if DEBUG
struct StartButtonView_Previews: PreviewProvider {
    static var previews: some View {
        StartButtonView()
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
    }
}
#endif

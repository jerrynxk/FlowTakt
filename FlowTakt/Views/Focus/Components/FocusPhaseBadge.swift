import SwiftUI

// MARK: - 阶段标识徽章

struct FocusPhaseBadge: View {
    @EnvironmentObject var focusViewModel: FocusViewModel
    @EnvironmentObject var l10n: L10n

    private var phaseText: String {
        switch focusViewModel.activePhase {
        case .focus:
            return L10n.shared.focus
        case .shortBreak:
            return L10n.shared.短休息
        case .longBreak:
            return L10n.shared.长休息
        }
    }

    private var phaseColor: Color {
        Color.forPhase(focusViewModel.activePhase)
    }

    private var phaseIcon: String {
        switch focusViewModel.activePhase {
        case .focus:
            return "flame.fill"
        case .shortBreak:
            return "cup.and.saucer.fill"
        case .longBreak:
            return "moon.stars.fill"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: phaseIcon)
                .font(.caption)
            Text(phaseText)
                .font(.caption.weight(.semibold))
        }
        .foregroundColor(phaseColor)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(phaseColor.opacity(0.12))
        .cornerRadius(12)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: focusViewModel.activePhase)
    }
}

#if DEBUG
struct FocusPhaseBadge_Previews: PreviewProvider {
    static var previews: some View {
        FocusPhaseBadge()
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

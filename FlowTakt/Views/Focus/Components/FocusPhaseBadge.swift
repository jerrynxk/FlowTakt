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
        HStack(spacing: 5) {
            Image(systemName: phaseIcon)
                .font(.caption2)
                // 无障碍补齐（2026-11-02）：装饰图标不单独朗读（"火焰"「专注」重复）
                .accessibilityHidden(true)
            Text(phaseText)
                .font(.caption2.weight(.semibold))
        }
        .foregroundColor(phaseColor)
        .accessibilityElement(children: .combine)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        // 视觉优化（2026-10-03）：改为 Capsule 并降低底色透明度。
        // 旧版 cornerRadius(12) + 0.12 底色在浅色圆底上略显厚重，
        // 且与外层圆环的柔和风格不统一。
        .background(
            Capsule()
                .fill(phaseColor.opacity(0.10))
        )
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
                    persistenceController: PersistenceController.shared
                ),
                taskService: TaskService(persistenceController: PersistenceController.shared),
                speechService: SpeechService()
            ))
            .environmentObject(L10n.shared)
    
}
}
#endif

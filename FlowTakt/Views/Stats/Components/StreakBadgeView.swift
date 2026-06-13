import SwiftUI

// MARK: - 连续天数视图

struct StreakBadgeView: View {
    @EnvironmentObject var statsViewModel: StatsViewModel
    @EnvironmentObject var l10n: L10n

    /// 是否有连续记录
    private var hasStreak: Bool {
        statsViewModel.currentStreak > 0
    }

    var body: some View {
        HStack(spacing: 20) {
            // 火焰图标
            ZStack {
                Circle()
                    .fill(hasStreak ? Color.orange.opacity(0.15) : Color(.systemGray5))
                    .frame(width: 64, height: 64)

                Image(systemName: "flame.fill")
                    .font(.system(size: 32))
                    .foregroundColor(hasStreak ? .orange : .gray)
                    .scaleEffect(hasStreak ? 1.0 : 0.85)
            }

            // 文字区域
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(statsViewModel.currentStreak)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(hasStreak ? .orange : .gray)

                    Text(L10n.shared.天)
                        .font(.title3)
                        .foregroundColor(hasStreak ? .orange : .gray)
                }

                Text(L10n.shared.连续专注)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // 装饰性火焰粒子效果（有连续时）
            if hasStreak {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundColor(.orange.opacity(0.5))
            }
        }
        .padding(16)
        .cardStyle()
    }
}

#if DEBUG
struct StreakBadgeView_Previews: PreviewProvider {
    static var previews: some View {
        StreakBadgeView()
            .environmentObject(StatsViewModel(
                focusService: FocusService(
                    persistenceController: PersistenceController.shared,
                    notificationService: NotificationService()
                ),
                taskService: TaskService(persistenceController: PersistenceController.shared),
                persistenceController: PersistenceController.shared
            ))
            .padding()
            .background(Color.appBackground)
    }
}
#endif

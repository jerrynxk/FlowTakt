import SwiftUI

// MARK: - 今日迷你统计

struct TodayMiniStatsView: View {
    @EnvironmentObject var statsViewModel: StatsViewModel
    @EnvironmentObject var l10n: L10n

    var body: some View {
        HStack(spacing: 32) {
            // 今日完成的番茄钟数
            statItem(
                icon: "checkmark.circle.fill",
                value: "\(statsViewModel.todaySessions.filter { $0.isCompleted }.count)",
                label: L10n.shared.今日完成,
                color: .focusRed
            )

            Divider()
                .frame(height: 30)

            // 今日获得积分
            statItem(
                icon: "star.fill",
                value: "\(statsViewModel.todaySessions.reduce(0) { $0 + $1.earnedPoints })",
                label: L10n.shared.今日积分,
                color: .orange
            )
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 24)
        .cardStyle()
        .onAppear {
            statsViewModel.refresh()
        }
    }

    // MARK: - 统计项

    private func statItem(icon: String, value: String, label: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}

#if DEBUG
struct TodayMiniStatsView_Previews: PreviewProvider {
    static var previews: some View {
        TodayMiniStatsView()
            .environmentObject(StatsViewModel(
                focusService: FocusService(
                    persistenceController: PersistenceController.shared,
                    notificationService: NotificationService()
                ),
                taskService: TaskService(persistenceController: PersistenceController.shared),
                persistenceController: PersistenceController.shared
            ))
            .padding()
    }
}
#endif

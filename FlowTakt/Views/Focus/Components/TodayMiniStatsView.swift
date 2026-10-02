import SwiftUI

// MARK: - 今日迷你统计

struct TodayMiniStatsView: View {
    @EnvironmentObject var statsViewModel: StatsViewModel
    @EnvironmentObject var l10n: L10n

    var body: some View {
        HStack(spacing: 0) {
            statItem(
                icon: "checkmark.circle.fill",
                value: "\(statsViewModel.todaySessions.filter { $0.isCompleted }.count)",
                label: L10n.shared.今日完成,
                color: .focusRed
            )
            .frame(maxWidth: .infinity)

            Rectangle()
                .fill(Color(.systemGray4))
                .frame(width: 1, height: 24)

            statItem(
                icon: "star.fill",
                value: "\(statsViewModel.todaySessions.reduce(0) { $0 + $1.earnedPoints })",
                label: L10n.shared.今日积分,
                color: .orange
            )
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .cardStyle()
        // 无障碍：整卡合并为一个可读元素（读屏朗读「今日完成 X，今日积分 Y」）
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(miniStatsAccessibilityLabel)
        .onAppear {
            statsViewModel.refresh()
        }
    }

    /// VoiceOver 整卡标签
    private var miniStatsAccessibilityLabel: String {
        let completed = statsViewModel.todaySessions.filter { $0.isCompleted }.count
        let points = statsViewModel.todaySessions.reduce(0) { $0 + $1.earnedPoints }
        return "\(L10n.shared.今日完成) \(completed)，\(L10n.shared.今日积分) \(points)"
    }

    // MARK: - 统计项（紧凑版：icon + 数字 + 标签横向）

    private func statItem(icon: String, value: String, label: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.callout)
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

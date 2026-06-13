import SwiftUI

// MARK: - 积分概览组件

struct PointsDisplayView: View {
    @EnvironmentObject var achievementViewModel: AchievementViewModel
    @EnvironmentObject var l10n: L10n

    var body: some View {
        HStack(spacing: 24) {
            // 总积分
            pointsCard(
                title: L10n.shared.totalPoints,
                points: achievementViewModel.totalPoints,
                icon: "star.fill",
                color: .yellow
            )

            // 分割线
            divider

            // 今日积分
            pointsCard(
                title: L10n.shared.todayPointsText,
                points: achievementViewModel.todayPoints,
                icon: "star.circle.fill",
                color: .orange
            )
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
    }

    // MARK: - 子组件

    private var divider: some View {
        Rectangle()
            .fill(Color(.separator))
            .frame(width: 1, height: 44)
    }

    private func pointsCard(title: String, points: Int, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(points)")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .animation(.spring(response: 0.3), value: points)

                Text(title)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(points)")
    }
}

// MARK: - 预览

#if DEBUG
struct PointsDisplayView_Previews: PreviewProvider {
    static var previews: some View {
        PointsDisplayView()
            .environmentObject(AchievementViewModel(
                achievementService: AchievementService(
                    persistenceController: PersistenceController.shared,
                    focusService: FocusService(
                        persistenceController: PersistenceController.shared,
                        notificationService: NotificationService()
                    )
                )
            ))
            .padding()
            .background(Color.appBackground)
            .previewLayout(.sizeThatFits)
    }
}
#endif

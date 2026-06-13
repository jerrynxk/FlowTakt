import SwiftUI

// MARK: - 洞察卡片视图

struct InsightCardView: View {
    @EnvironmentObject var statsViewModel: StatsViewModel
    @EnvironmentObject var l10n: L10n

    /// 今日已完成的番茄钟数
    private var todayCompletedCount: Int {
        statsViewModel.todaySessions.filter { $0.isCompleted }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            // 标题
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.focusRed)
                Text(L10n.shared.数据洞察)
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            // 洞察条目
            VStack(alignment: .leading, spacing: 14) {
                InsightRow(
                    icon: "checkmark.circle.fill",
                    iconColor: .focusRed,
                    text: L10n.shared.todayCompleted(todayCompletedCount)
                )

                InsightRow(
                    icon: "flame.fill",
                    iconColor: .orange,
                    text: L10n.shared.longestStreak(statsViewModel.currentStreak)
                )

                InsightRow(
                    icon: "number.circle.fill",
                    iconColor: .breakGreen,
                    text: L10n.shared.totalCompleted(statsViewModel.totalCompletedPomodoros)
                )
            }
            .padding(16)
        }
        .cardStyle()
    }
}

// MARK: - 洞察行

private struct InsightRow: View {
    let icon: String
    let iconColor: Color
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(iconColor)
                .frame(width: 24)

            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)

            Spacer()
        }
    }
}

#if DEBUG
struct InsightCardView_Previews: PreviewProvider {
    static var previews: some View {
        InsightCardView()
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

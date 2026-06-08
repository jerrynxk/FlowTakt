import SwiftUI

// MARK: - 洞察卡片视图

struct InsightCardView: View {
    @EnvironmentObject var statsViewModel: StatsViewModel

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
                Text("数据洞察")
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
                    text: "今天已完成 \(todayCompletedCount) 个番茄钟"
                )

                InsightRow(
                    icon: "flame.fill",
                    iconColor: .orange,
                    text: "最长连续专注 \(statsViewModel.currentStreak) 天"
                )

                InsightRow(
                    icon: "number.circle.fill",
                    iconColor: .breakGreen,
                    text: "累计完成 \(statsViewModel.totalCompletedPomodoros) 个番茄钟"
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

import SwiftUI

// MARK: - 今日概览卡片

struct TodayOverviewCard: View {
    @EnvironmentObject var statsViewModel: StatsViewModel

    /// 今日已完成的番茄钟数
    private var todayCompletedCount: Int {
        statsViewModel.todaySessions.filter { $0.isCompleted }.count
    }

    /// 今日获得的积分
    private var todayPoints: Int {
        todayCompletedCount * AppConstants.pointsPerCompletedPomodoro
    }

    var body: some View {
        VStack(spacing: 0) {
            // 标题
            HStack {
                Image(systemName: "sun.max.fill")
                    .foregroundColor(.focusRed)
                Text("今日概览")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            // 主内容
            HStack(spacing: 24) {
                // 左侧：数字区域
                VStack(alignment: .leading, spacing: 12) {
                    // 番茄钟数
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(todayCompletedCount)")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundColor(.focusRed)

                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.focusRed)
                            Text("个番茄钟已完成")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    // 专注时长
                    if statsViewModel.todayDuration > 0 {
                        HStack(spacing: 6) {
                            Image(systemName: "clock.fill")
                                .font(.caption)
                                .foregroundColor(.focusRed.opacity(0.7))
                            Text(statsViewModel.todayDuration.formattedDuration)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                        }
                    }

                    // 积分
                    HStack(spacing: 6) {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundColor(.yellow)
                        Text("+\(todayPoints) 积分")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // 右侧：进度环
                ZStack {
                    // 背景环
                    Circle()
                        .stroke(Color(.systemGray5), lineWidth: 8)

                    // 前景环
                    Circle()
                        .trim(from: 0, to: statsViewModel.completionRate)
                        .stroke(
                            AngularGradient(
                                gradient: Gradient(colors: [.focusRed, .focusRed.opacity(0.6)]),
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.8), value: statsViewModel.completionRate)

                    // 中心文字
                    VStack(spacing: 2) {
                        Text("\(Int(statsViewModel.completionRate * 100))%")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.focusRed)
                        Text("完成率")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 80, height: 80)
            }
            .padding(16)
        }
        .cardStyle()
    }
}

#if DEBUG
struct TodayOverviewCard_Previews: PreviewProvider {
    static var previews: some View {
        TodayOverviewCard()
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

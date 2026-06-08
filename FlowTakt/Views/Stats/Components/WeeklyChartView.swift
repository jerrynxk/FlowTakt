import SwiftUI

// MARK: - 周度图表视图

struct WeeklyChartView: View {
    @EnvironmentObject var statsViewModel: StatsViewModel

    /// 简体中文星期标签
    private let dayLabels = ["一", "二", "三", "四", "五", "六", "日"]

    /// 柱状图最大高度
    private let barMaxHeight: CGFloat = 120

    /// 柱状图最小高度（始终可辨）
    private let barMinHeight: CGFloat = 4

    /// 今日的索引（从周日=0 转为一=0 的偏移）
    private var todayWeekdayIndex: Int {
        let weekday = Calendar.current.component(.weekday, from: Date())
        // weekday: 1=周日, 2=周一 ... 7=周六
        // 转为: 0=周一, 1=周二 ... 6=周日
        return (weekday + 5) % 7
    }

    var body: some View {
        VStack(spacing: 0) {
            // 标题
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundColor(.focusRed)
                Text("本周趋势")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            // 柱状图
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(Array(statsViewModel.weeklyData.enumerated()), id: \.offset) { index, dailyStat in
                    let isToday = index == statsViewModel.weeklyData.count - 1
                    let maxPomodoros = statsViewModel.weeklyData.map(\.completedPomodoros).max() ?? 1
                    let ratio = maxPomodoros > 0
                        ? CGFloat(dailyStat.completedPomodoros) / CGFloat(maxPomodoros)
                        : 0
                    let barHeight = max(barMinHeight, ratio * barMaxHeight)

                    VStack(spacing: 6) {
                        // 数值（柱顶）
                        Text("\(dailyStat.completedPomodoros)")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(isToday ? .focusRed : .secondary)

                        // 柱体
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        .focusRed,
                                        isToday ? .focusRed : .focusRed.opacity(0.5)
                                    ]),
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                            .frame(width: 24, height: barHeight)
                            .opacity(isToday ? 1.0 : 0.7)
                            .scaleEffect(isToday ? 1.05 : 1.0)

                        // 标签
                        Text(dayLabels[index])
                            .font(.system(size: 12, weight: isToday ? .bold : .regular))
                            .foregroundColor(isToday ? .focusRed : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        .cardStyle()
    }
}

#if DEBUG
struct WeeklyChartView_Previews: PreviewProvider {
    static var previews: some View {
        WeeklyChartView()
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

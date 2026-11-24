import SwiftUI

// MARK: - 今日概览卡片

struct TodayOverviewCard: View {
    @EnvironmentObject var statsViewModel: StatsViewModel
    @EnvironmentObject var l10n: L10n

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
                Text(L10n.shared.今日概览)
                    .font(.headline)
                    .foregroundColor(.primary)
                    // 无障碍（2026-10-14）：卡片标题标记为二级标题（与周趋势/年热力图一致）
                    .accessibilityHeading(.h2)
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

                        Text(L10n.shared.todayCompleted(todayCompletedCount))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // 专注时长（用户反馈 2026-11-19）：始终显示 —— 番茄时长可自定义，
                    // 「完成了几个」不足以反映投入；时长才是可比较的指标。
                    // 同时补上文字标签（原来只有图标+数字，用户不知道这是什么）。
                    HStack(spacing: 6) {
                        Image(systemName: "clock.fill")
                            .font(.caption)
                            .foregroundColor(.focusRed.opacity(0.7))
                        Text(statsViewModel.todayDuration.formattedDuration)
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundColor(.primary)
                        Text(L10n.shared.专注时长)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // 积分
                    HStack(spacing: 6) {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundColor(.yellow)
                        Text(L10n.shared.todayPoints(todayPoints))
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
                        Text(L10n.shared.完成率)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 80, height: 80)
            }
            .padding(16)
        }
        .cardStyle()
        // 无障碍（2026-10-14）：整卡合并为一个可读元素（此前读屏需逐个划过数字/图标/进度环）
        .accessibilityElement(children: .combine)
        .accessibilityLabel(overviewAccessibilityLabel)
    }

    /// VoiceOver 整卡标签：「今日概览，今日完成 X 个，专注 Y，积分 Z，完成率 N%」
    private var overviewAccessibilityLabel: String {
        var parts = [L10n.shared.今日概览, L10n.shared.todayCompleted(todayCompletedCount)]
        parts.append("\(L10n.shared.专注时长) \(statsViewModel.todayDuration.formattedDuration)")
        parts.append(L10n.shared.todayPoints(todayPoints))
        parts.append("\(L10n.shared.完成率) \(Int(statsViewModel.completionRate * 100))%")
        return parts.joined(separator: "，")
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
            .environmentObject(L10n.shared)
    
}
}
#endif

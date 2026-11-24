import SwiftUI

// MARK: - 今日概览仪表盘（专注工具条「统计」入口，2026-11-22 重设计）
//
// 旧版仅一个三列数字卡，信息扁平、观感单薄（用户反馈「太难看」），已整体替换。
// 新版四段式：标题日期 → Hero（今日时长 + 完成率环）→ 三指标卡 → 近 7 天柱状趋势。
// 本视图零统计逻辑：所有数据读自 StatsViewModel，口径与统计页完全收口；
// 统计视图（StatsViewModel）由外层 EnvironmentObject 注入，onAppear 触发 refresh。

struct TodayOverviewSheetView: View {
    @EnvironmentObject var statsViewModel: StatsViewModel
    @EnvironmentObject var l10n: L10n

    private let calendar = Calendar.current

    // MARK: 派生数据（口径全部沿用 StatsViewModel，不另算）

    private var completedCount: Int {
        statsViewModel.todaySessions.filter { $0.isCompleted }.count
    }

    private var points: Int {
        Int(statsViewModel.todaySessions.reduce(Int16(0)) { $0 + $1.earnedPoints })
    }

    /// 连续天数（0 时仍显示，让用户看到当前状态）
    private var streakDays: Int {
        statsViewModel.currentStreak
    }

    /// 柱状图最高柱对应的时长，用于归一化；全 0 时给 1 避免除零
    private var maxDayDuration: TimeInterval {
        max(statsViewModel.weeklyData.map(\.totalDuration).max() ?? 0, 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            // 上下 Spacer 均分剩余高度，让内容整体在固定高度弹层里垂直居中（用户要求 2026-11-22）
            Spacer(minLength: 0)
            VStack(spacing: 16) {
                header
                heroCard
                metricsRow
                weeklyTrendCard
            }
            .padding(.horizontal, 20)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 忽略 sheet 上下安全区，让 Spacer 在整个弹层高度里均分，视觉才真正上下居中
        .ignoresSafeArea()
        .background(Color.appBackground)
        .onAppear { statsViewModel.refresh() }
    }

    // MARK: - 标题 + 日期

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(l10n.今日概览)
                .font(.title2.weight(.bold))
                .foregroundColor(.primary)
                .accessibilityHeading(.h1)
            Spacer()
            Text(todayDateText)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Hero：今日专注时长（大数字）+ 完成率环

    private var heroCard: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(l10n.今日专注时长)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.secondary)

                Text(statsViewModel.todayDuration.formattedDuration)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.focusRed)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)

                Text(l10n.todayCompleted(completedCount))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 8)

            completionRing
        }
        .padding(18)
        .cardStyle()
        .accessibilityElement(children: .combine)
    }

    /// 完成率进度环（沿用统计页 TodayOverviewCard 的样式：focusRed 渐变环 + 中心百分比）
    private var completionRing: some View {
        let rate = min(max(statsViewModel.completionRate, 0), 1)
        return ZStack {
            Circle()
                // 底环用 focusRed 低透明度（与柱状图同色系），确保 0% 时空环在深色卡片上也清晰可见
                .stroke(Color.focusRed.opacity(0.2), lineWidth: 9)

            Circle()
                .trim(from: 0, to: rate)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [.focusRed, .focusRed.opacity(0.55)]),
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 9, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.6), value: rate)

            VStack(spacing: 1) {
                Text("\(Int(rate * 100))%")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundColor(.focusRed)
                Text(l10n.完成率)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 88, height: 88)
        .accessibilityLabel("\(l10n.完成率) \(Int(rate * 100))%")
    }

    // MARK: - 三指标卡

    private var metricsRow: some View {
        HStack(spacing: 10) {
            metricCard(
                icon: "checkmark.circle.fill",
                value: "\(completedCount)",
                label: l10n.今日完成,
                color: .focusRed
            )
            metricCard(
                icon: "star.fill",
                value: "\(points)",
                label: l10n.今日积分,
                color: .orange
            )
            metricCard(
                icon: "flame.fill",
                value: "\(streakDays)",
                label: l10n.连续专注,
                color: .longBreakBlue
            )
        }
    }

    private func metricCard(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(color)
                .accessibilityHidden(true)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.cardInsetFill)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value)")
    }

    // MARK: - 近 7 天柱状趋势

    private var weeklyTrendCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(l10n.近7天专注)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .accessibilityHeading(.h2)
                Spacer()
            }

            HStack(alignment: .bottom, spacing: 10) {
                ForEach(statsViewModel.weeklyData) { day in
                    bar(for: day)
                }
            }
            .frame(height: 110)
        }
        .padding(16)
        .cardStyle()
    }

    /// 单日柱：柱子高度按当日时长归一化，今天用 focusRed 高亮，其余用 focusRed 低透明度
    private func bar(for day: DailyStats) -> some View {
        let isToday = calendar.isDateInToday(day.date)
        let ratio = CGFloat(day.totalDuration / maxDayDuration)
        let label = weekdayLabel(for: day.date)

        return VStack(spacing: 6) {
            // 时长数值（仅有数据的天显示，避免一片 0）
            if day.totalDuration > 0 {
                Text(day.totalDuration.formattedDuration)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Text("")
                    .font(.system(size: 9))
            }

            GeometryReader { geo in
                let barHeight = max(4, geo.size.height * ratio)
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isToday ? Color.focusRed : Color.focusRed.opacity(0.32))
                    .frame(height: barHeight)
                    .frame(maxWidth: .infinity, alignment: .bottom)
            }

            Text(label)
                .font(.caption2)
                .foregroundColor(isToday ? .focusRed : .secondary)
                .fontWeight(isToday ? .semibold : .regular)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(barAccessibilityLabel(day: day, isToday: isToday))
    }

    // MARK: - Helpers

    private var todayDateText: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: Date())
    }

    /// Calendar 周日 = 1 → 映射到 L10n 的「日」「一」…「六」
    private func weekdayLabel(for date: Date) -> String {
        let w = calendar.component(.weekday, from: date) // 1=Sun ... 7=Sat
        switch w {
        case 1: return l10n.日
        case 2: return l10n.一
        case 3: return l10n.二
        case 4: return l10n.三
        case 5: return l10n.四
        case 6: return l10n.五
        default: return l10n.六
        }
    }

    private func barAccessibilityLabel(day: DailyStats, isToday: Bool) -> String {
        let prefix = isToday ? l10n.今日 : ""
        // 中性番茄数文案：历史日期不能用 todayCompleted（会误读成「今天已完成」）
        return "\(prefix)\(weekdayLabel(for: day.date)) \(l10n.专注时长) \(day.totalDuration.formattedDuration)，\(l10n.estimatedPomodoros(day.completedPomodoros))"
    }
}

#if DEBUG
struct TodayOverviewSheetView_Previews: PreviewProvider {
    static var previews: some View {
        TodayOverviewSheetView()
            .environmentObject(StatsViewModel(
                focusService: FocusService(
                    persistenceController: PersistenceController.shared,
                    notificationService: NotificationService()
                ),
                taskService: TaskService(persistenceController: PersistenceController.shared),
                persistenceController: PersistenceController.shared
            ))
            .environmentObject(L10n.shared)
    }
}
#endif

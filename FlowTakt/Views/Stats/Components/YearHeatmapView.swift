import SwiftUI

// MARK: - 专注年热力图（A5）
// GitHub 风格：过去一年（53 周 × 7 天）按日完成番茄数着色。

struct YearHeatmapView: View {
    @EnvironmentObject var statsViewModel: StatsViewModel
    @EnvironmentObject var l10n: L10n

    private let calendar = Calendar.current

    /// 月份标签格式化器（静态缓存，避免每帧创建）
    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = "M"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 标题
            HStack {
                Image(systemName: "calendar")
                    .foregroundColor(.focusRed)
                Text(l10n.专注年热力图)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .accessibilityHeading(.h2)
                Spacer()
                Text(l10n.年打卡天数(statsViewModel.yearlyTotalDays))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            heatmapGrid
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

            // 图例
            HStack(spacing: 5) {
                Text(l10n.少)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                ForEach(0..<5, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color(forLevel: level))
                        .frame(width: 11, height: 11)
                }
                Text(l10n.多)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .cardStyle()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(l10n.专注年热力图
            + "：" + l10n.年打卡天数(statsViewModel.yearlyTotalDays))
    }

    private var heatmapGrid: some View {
        let end = calendar.startOfDay(for: Date())
        // 审查修复（2026-08-12）：旧实现只回退到本周首（weekdayEnd-1），网格只渲染本周 7 天，
        // 与「53 周×7 天」标题及全年数据不符。改为回退 364 天（52 周）再对齐周首，覆盖过去一年。
        guard let backDate = calendar.date(byAdding: .day, value: -364, to: end) else {
            return AnyView(EmptyView())
        }
        let weekdayBack = calendar.component(.weekday, from: backDate)
        guard let gridStart = calendar.date(byAdding: .day, value: -(weekdayBack - 1), to: backDate) else {
            return AnyView(EmptyView())
        }
        let totalDays = calendar.dateComponents([.day], from: gridStart, to: end).day ?? 0
        let columnCount = max(1, Int(ceil(Double(totalDays + 1) / 7.0)))

        // 预生成列（含月份标签）
        var columns: [[Date]] = []
        var monthLabels: [(offset: Int, text: String)] = []
        var day = gridStart
        for col in 0..<columnCount {
            var column: [Date] = []
            for _ in 0..<7 {
                column.append(day)
                day = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            }
            columns.append(column)
            // 该列含某月 1 号或跨月首列 → 标月份
            if let firstOfMonth = column.first(where: { calendar.component(.day, from: $0) == 1 }) {
                monthLabels.append((col, Self.monthFormatter.string(from: firstOfMonth)))
            }
        }

        return AnyView(
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    // 月份标签行
                    HStack(alignment: .top, spacing: 3) {
                        ForEach(monthLabels, id: \.offset) { label in
                            Text(label.text)
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                                .frame(width: 11)
                                .offset(x: CGFloat(label.offset) * 14, y: 0)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(height: 12)
                    .padding(.leading, 0)

                    // 格子行（每行 53 列中的一格）
                    HStack(alignment: .top, spacing: 3) {
                        ForEach(columns.indices, id: \.self) { ci in
                            VStack(spacing: 3) {
                                ForEach(columns[ci], id: \.self) { d in
                                    cell(date: d, isFuture: d > end)
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, 2)
            }
        )
    }

    private func cell(date: Date, isFuture: Bool) -> some View {
        let key = calendar.startOfDay(for: date)
        let count = statsViewModel.yearlyCounts[key] ?? 0
        return RoundedRectangle(cornerRadius: 2)
            .fill(isFuture ? Color(.systemGray5).opacity(0.4) : color(forCount: count))
            .frame(width: 11, height: 11)
            .accessibilityHidden(true)
    }

    private func color(forCount count: Int) -> Color {
        switch count {
        case 0:  return Color(.systemGray6)
        case 1:  return Color.focusRed.opacity(0.25)
        case 2:  return Color.focusRed.opacity(0.45)
        case 3:  return Color.focusRed.opacity(0.7)
        default: return Color.focusRed
        }
    }

    private func color(forLevel level: Int) -> Color {
        switch level {
        case 0:  return Color(.systemGray6)
        case 1:  return Color.focusRed.opacity(0.25)
        case 2:  return Color.focusRed.opacity(0.45)
        case 3:  return Color.focusRed.opacity(0.7)
        default: return Color.focusRed
        }
    }
}

#Preview {
    YearHeatmapView()
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

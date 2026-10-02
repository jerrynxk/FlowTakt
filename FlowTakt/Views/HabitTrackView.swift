import SwiftUI
import CoreData

// MARK: - 习惯追踪视图（习惯 + 计时）

struct HabitTrackView: View {
    @EnvironmentObject var habitViewModel: HabitViewModel
    @EnvironmentObject var timeRecordViewModel: TimeRecordViewModel
    @EnvironmentObject var taskViewModel: TaskViewModel
    @EnvironmentObject var l10n: L10n

    @State private var selectedTab: TrackTab = .habit

    enum TrackTab: CaseIterable {
        case habit
        case heatmap
        case timer
    }

    var body: some View {
        // v1.3.4p：iPad 全量适配 — VStack 整体限宽 700pt 居中
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                ForEach(TrackTab.allCases, id: \.self) { tab in
                    switch tab {
                    case .habit:   return Text(l10n.习惯).tag(tab)
                    case .heatmap: return Text(l10n.热力图).tag(tab)
                    case .timer:   return Text(l10n.计时).tag(tab)
                    }
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            switch selectedTab {
            case .habit:
                HabitListView()
            case .heatmap:
                HabitHeatmapView()
            case .timer:
                TimeRecordView()
                    .environmentObject(taskViewModel)
            }
        }
        // v1.3.4p：iPad 上 NavigationSplitView detail 内的 frame(maxWidth:) 失效（SwiftUI 限制），
        // List/Picker 在 iPad 保持自然宽度（参考邮件/备忘录）
    }
}

// MARK: - 打卡热力图

/// 按月/周可视化习惯打卡密度（GitHub 风格热力图）。
/// 数据经 HabitViewModel → HabitService 按区间查询聚合（遵循 VM → Service 架构约定）。
struct HabitHeatmapView: View {
    @EnvironmentObject var habitViewModel: HabitViewModel
    @EnvironmentObject var l10n: L10n
    // v1.3.4p：iPad 全量适配 — 热力图格子放大
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private let calendar = Calendar.current
    private let weeks = 17

    /// 格子尺寸：iPad（regular）18pt，iPhone 14pt
    private var cellSize: CGFloat {
        horizontalSizeClass == .regular ? 18 : 14
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 20) {
                    statBlock(value: "\(habitViewModel.heatmapTotalCheckIns)", label: l10n.打卡次数)
                    statBlock(value: "\(habitViewModel.heatmapCounts.values.filter { $0 > 0 }.count)", label: l10n.打卡天数)
                }
                .frame(maxWidth: .infinity, alignment: .center)

                heatmapGrid
                    .frame(maxWidth: .infinity, alignment: .center)

                HStack(spacing: 6) {
                    Text(l10n.热力图图例)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    ForEach(0..<5, id: \.self) { level in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(color(forLevel: level))
                            .frame(width: cellSize * 0.85, height: cellSize * 0.85)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding()
        }
        .background(Color.appBackground)
        .navigationTitle(l10n.打卡热力图)
        // 幂等加载：VM 已在其上下文变化订阅中自动刷新，此处兜底首次进入
        .task { habitViewModel.reloadHeatmap(weeks: weeks) }
    }

    private var heatmapGrid: some View {
        let end = calendar.startOfDay(for: Date())
        // 审查修复（2026-08-12）：旧实现只回退到本周周一，columnCount 恒为 1，网格只渲染本周
        // 7 天，与数据源（17 周）和顶部统计严重不符。改为回退 17 周再对齐周首，动态列数覆盖到今天。
        let totalBackDays = weeks * 7 - 1
        guard let backDate = calendar.date(byAdding: .day, value: -totalBackDays, to: end) else {
            return AnyView(EmptyView())
        }
        let weekdayBack = (calendar.component(.weekday, from: backDate) + 5) % 7   // 0=周一 ... 6=周日
        guard let gridStart = calendar.date(byAdding: .day, value: -weekdayBack, to: backDate) else {
            return AnyView(EmptyView())
        }
        let totalDays = calendar.dateComponents([.day], from: gridStart, to: end).day ?? 0
        let columnCount = max(1, Int(ceil(Double(totalDays + 1) / 7.0)))
        var columns: [[Date]] = []
        var day = gridStart
        for _ in 0..<columnCount {
            var col: [Date] = []
            for _ in 0..<7 {
                col.append(day)
                day = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            }
            columns.append(col)
        }
        return AnyView(
            HStack(alignment: .top, spacing: 4) {
                ForEach(columns.indices, id: \.self) { ci in
                    VStack(spacing: 4) {
                        ForEach(columns[ci], id: \.self) { d in
                            cell(date: d, isFuture: d > end)
                        }
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                l10n.打卡热力图 + "，" + l10n.打卡次数 + " \(habitViewModel.heatmapTotalCheckIns)"
            )
        )
    }

    private func cell(date: Date, isFuture: Bool) -> some View {
        let key = calendar.startOfDay(for: date)
        let count = habitViewModel.heatmapCounts[key] ?? 0
        return RoundedRectangle(cornerRadius: 3)
            .fill(isFuture ? Color(.systemGray6) : color(forCount: count))
            .frame(width: cellSize, height: cellSize)
            .opacity(isFuture ? 0.35 : 1)
            .accessibilityHidden(true)
    }

    private func color(forCount count: Int) -> Color {
        switch count {
        case 0: return Color(.systemGray5)
        case 1: return Color.focusRed.opacity(0.35)
        case 2...3: return Color.focusRed.opacity(0.6)
        case 4...5: return Color.focusRed.opacity(0.8)
        default: return Color.focusRed
        }
    }

    private func color(forLevel level: Int) -> Color {
        color(forCount: [0, 1, 2, 4, 99][level])
    }

    private func statBlock(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.focusRed)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        // 无障碍：数字+标签合并朗读（避免读屏逐字读）
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(value)")
    }
}

#Preview {
    HabitTrackView()
        .environmentObject(HabitViewModel(
            habitService: HabitService(persistenceController: .shared),
            persistenceController: .shared
        ))
        .environmentObject(TimeRecordViewModel(
            timeRecordService: TimeRecordService(persistenceController: .shared),
            persistenceController: .shared
        ))
        .environmentObject(TaskViewModel(
            taskService: TaskService(persistenceController: .shared),
            persistenceController: .shared
        ))
}

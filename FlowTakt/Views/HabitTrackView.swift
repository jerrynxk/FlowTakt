import SwiftUI
import CoreData

// MARK: - 习惯追踪视图（习惯 + 热力图）
// 2026-11-22：「计时」段移除 —— 正计时统一收敛到「专注」页（TimeRecordView embedded 形态）。
// 原独立计时页独有的「查看历史日期 + 删除记录」能力已补进专注页正计时，功能无损。

struct HabitTrackView: View {
    @EnvironmentObject var habitViewModel: HabitViewModel
    @EnvironmentObject var l10n: L10n
    // v1.3.5 iPad 复查 M2：regular 下分段控件按内容宽度收缩，避免两段各拉满约 500pt
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var selectedTab: TrackTab = .habit

    enum TrackTab: CaseIterable {
        case habit
        case heatmap
    }

    var body: some View {
        // v1.3.4p：iPad 全量适配 — VStack 整体限宽 700pt 居中
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                ForEach(TrackTab.allCases, id: \.self) { tab in
                    switch tab {
                    case .habit:   return Text(l10n.习惯).tag(tab)
                    case .heatmap: return Text(l10n.热力图).tag(tab)
                    }
                }
            }
            .pickerStyle(.segmented)
            // v1.3.5 iPad 复查 M2：iPad（regular）detail 区约 1000pt，分段控件默认拉满全宽，
            // 3→2 段后每段约 500pt、文字显小。用 .fixedSize() 按内容宽收缩（不受 detail 内
            // frame(maxWidth:) 失效限制），外层空出的宽度由 Spacer 吸收实现居中。
            // iPhone（compact）保持拉满，不改既有手感。
            .if(horizontalSizeClass == .regular) { $0.fixedSize() }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            // 无障碍（2026-11-22 审查 L1）：原 label 设为「习惯」与首段同名，读屏出现
            // 容器与选项同名。改用中性的用途标签「视图切换」，两段文字由 segmented 子选项暴露。
            .accessibilityLabel(l10n.视图切换)
            .accessibilityIdentifier("topTabPicker")

            switch selectedTab {
            case .habit:
                HabitListView()
            case .heatmap:
                HabitHeatmapView()
            }
        }
        // 左右滑动切换顶部「习惯 / 热力图」标签（与竖向滚动不冲突）
        .swipeToSwitchTab(
            onSwipeLeft: { moveHabitTab(by: 1) },
            onSwipeRight: { moveHabitTab(by: -1) }
        )
        // v1.3.4p：iPad 上 NavigationSplitView detail 内的 frame(maxWidth:) 失效（SwiftUI 限制），
        // List/Picker 在 iPad 保持自然宽度（参考邮件/备忘录）
    }

    /// 按方向切换顶部标签（向左 = 下一个，向右 = 上一个），边界处夹紧不回环
    private func moveHabitTab(by direction: Int) {
        let order = TrackTab.allCases
        guard let idx = order.firstIndex(of: selectedTab) else { return }
        let newIdx = min(max(idx + direction, 0), order.count - 1)
        if newIdx != idx {
            selectedTab = order[newIdx]
        }
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
        VStack(spacing: 0) {
            // 标题行：「打卡热力图」大标题（本页无操作按钮），紧贴顶部分段控件（2026-10-14）。
            // 与「习惯」子页保持同构，消除系统大标题的导航栏空档。
            titleRow

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
                        Text(l10n.少)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        ForEach(0..<5, id: \.self) { level in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(color(forLevel: level))
                                .frame(width: cellSize * 0.85, height: cellSize * 0.85)
                                // 无障碍补齐（2026-11-02）：色块不含文本，避免在读屏里
                                // 留下 5 个无标签的空白元素
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    // 无障碍补齐（2026-11-02）：整组图例用一句说明替代「少」+ 5 个空色块
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(l10n.热力图图例说明)
                }
                .padding()
            }
            .background(Color.appBackground)
            .disableBounce()
        }
        .background(Color.appBackground)
        .navigationTitle(l10n.打卡热力图)
        // 隐藏系统导航栏，标题行成为内容首项、紧贴顶部分段控件。
        // 保留 navigationTitle 供 VoiceOver / 深链标题使用。
        .toolbar(.hidden, for: .navigationBar)
        // 幂等加载：VM 已在其上下文变化订阅中自动刷新，此处兜底首次进入
        .task { habitViewModel.reloadHeatmap(weeks: weeks) }
    }

    // MARK: - Title Row

    /// 标题行：「打卡热力图」大标题（本页无操作按钮）。
    /// 规格对齐 TaskListView.titleRow：largeTitle.bold、水平边距 16。
    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(l10n.打卡热力图)
                .font(.largeTitle.weight(.bold))
                // 无障碍（2026-10-14）：大标题标记为一级标题（VoiceOver 转子可按标题跳转）
                .accessibilityHeading(.h1)
            Spacer(minLength: 12)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 4)
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
            // 2026-11-02：isFuture 原为 systemGray6 —— 深色下 #1C1C1E 与列表行背景
            // 同色，未来日期格子完全不可见（此格与"未打卡"格子的唯一区别就是底色）。
            // 统一改用 systemGray5，靠 opacity 0.35 区分"未来"语义。
            .fill(isFuture ? Color(.systemGray5) : color(forCount: count))
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
        .environmentObject(L10n.shared)
}

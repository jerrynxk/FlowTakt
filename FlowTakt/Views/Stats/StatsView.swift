import SwiftUI

// MARK: - 统计主视图

struct StatsView: View {
    @EnvironmentObject var statsViewModel: StatsViewModel
    @EnvironmentObject var taskViewModel: TaskViewModel
    @EnvironmentObject var l10n: L10n

    @State private var showShareSheet = false
    @State private var shareImage: UIImage?

    /// 周报日期格式化器（审查修复：static 缓存，替代内联创建）
    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f
    }()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 标题行：「统计」大标题 + 「分享」按钮（同一行），紧贴顶部分段控件（2026-10-14）。
                // 原先分享按钮挂在导航栏 primaryAction、大标题由 .large 模式渲染，
                // 系统把按钮渲染在标题上方并额外预留导航栏高度，视觉上下分离；
                // 现改为内容区自绘标题行，与「任务」页（TaskListView）保持同构。
                titleRow

                ScrollView {
                    VStack(spacing: 16) {
                        TodayOverviewCard()
                            .environmentObject(statsViewModel)

                        // 总专注时长（今日/本周/本月/累计）—— 用户反馈 2026-11-19：
                        // 番茄时长可自定义，只展示番茄数参考价值有限
                        DurationSummaryCard()
                            .environmentObject(statsViewModel)

                        // 按标签耗时分布（全部/年/月/周/自定义，用户反馈 2026-11-22 扩展）
                        TagDurationCard()
                            .environmentObject(statsViewModel)

                        WeeklyChartView()
                            .environmentObject(statsViewModel)

                        // 专注年热力图（A5）
                        YearHeatmapView()
                            .environmentObject(statsViewModel)

                        TaskBreakdownView()
                            .environmentObject(taskViewModel)

                        StreakBadgeView()
                            .environmentObject(statsViewModel)

                        InsightCardView()
                            .environmentObject(statsViewModel)
                    }
                    .padding()
                }
                .background(Color.appBackground.ignoresSafeArea())
                .disableBounce()
            }
            .background(Color.appBackground)
            .navigationTitle(L10n.shared.统计)
            // 隐藏系统导航栏，标题行成为内容首项、紧贴顶部分段控件。
            // 保留 navigationTitle 供 VoiceOver / 深链标题使用。
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showShareSheet) {
                if let image = shareImage {
                    ShareSheet(items: [image])
                }
            }
        }
    }

    // MARK: - Title Row

    /// 标题行：「统计」大标题 + 「分享周报」按钮（同一行）。
    /// 规格对齐 TaskListView.titleRow：largeTitle.bold、水平边距 16、按钮 44×44 命中区、focusRed 着色。
    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(L10n.shared.统计)
                .font(.largeTitle.weight(.bold))
                // 无障碍（2026-10-14）：大标题标记为一级标题（VoiceOver 转子可按标题跳转）
                .accessibilityHeading(.h1)
            Spacer(minLength: 12)
            // 周报分享卡片（B3）
            Button {
                shareImage = weeklyReportImage
                showShareSheet = true
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.focusRed)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.shared.分享周报)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 4)
    }

    /// 渲染周报分享卡片为图片（3x 保证清晰度）
    private var weeklyReportImage: UIImage? {
        let weekLabel: String
        if let first = statsViewModel.weeklyData.first, let last = statsViewModel.weeklyData.last {
            // weeklyData[0]=今天、末位=6 天前（审查 #15）：显示顺序应为 起始 – 今天
            weekLabel = "\(Self.weekdayFormatter.string(from: last.date)) – \(Self.weekdayFormatter.string(from: first.date))"
        } else {
            weekLabel = ""
        }
        let card = WeeklyReportCardView(
            weekLabel: weekLabel,
            completedPomodoros: statsViewModel.weeklyData.reduce(0) { $0 + $1.completedPomodoros },
            totalMinutes: Int(statsViewModel.weeklyData.reduce(0) { $0 + $1.totalDuration } / 60),
            streak: statsViewModel.currentStreak,
            totalCompleted: statsViewModel.totalCompletedPomodoros
        )
        .frame(width: 360, height: 460)

        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        return renderer.uiImage
    }
}

#if DEBUG
struct StatsView_Previews: PreviewProvider {
    static var previews: some View {
        StatsView()
            .environmentObject(StatsViewModel(
                focusService: FocusService(
                    persistenceController: PersistenceController.shared,
                    notificationService: NotificationService()
                ),
                taskService: TaskService(persistenceController: PersistenceController.shared),
                persistenceController: PersistenceController.shared
            ))
            .environmentObject(TaskViewModel(
                taskService: TaskService(persistenceController: PersistenceController.shared),
                persistenceController: PersistenceController.shared
            ))
            .environmentObject(L10n.shared)
    
}
}
#endif

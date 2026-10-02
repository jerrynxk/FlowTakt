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
            ScrollView {
                VStack(spacing: 16) {
                    TodayOverviewCard()
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
            .navigationTitle(L10n.shared.统计)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    // 周报分享卡片（B3）
                    Button {
                        shareImage = weeklyReportImage
                        showShareSheet = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .fontWeight(.semibold)
                    }
                    .accessibilityLabel(L10n.shared.分享周报)
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let image = shareImage {
                    ShareSheet(items: [image])
                }
            }
            .refreshable {
                statsViewModel.refresh()
            }
        }
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
    }
}
#endif

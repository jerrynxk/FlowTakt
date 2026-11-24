import SwiftUI

// MARK: - 统计总览视图（统计 + 成就）

struct StatsOverviewView: View {
    @EnvironmentObject var statsViewModel: StatsViewModel
    @EnvironmentObject var achievementViewModel: AchievementViewModel
    @EnvironmentObject var l10n: L10n

    @State private var selectedTab: OverviewTab = .stats

    enum OverviewTab: CaseIterable {
        case stats
        case achievements
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                ForEach(OverviewTab.allCases, id: \.self) { tab in
                    switch tab {
                    case .stats:       Text(L10n.shared.统计).tag(tab)
                    case .achievements: Text(L10n.shared.成就).tag(tab)
                    }
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            // 无障碍（2026-10-14）：分段控件补用途标签
            .accessibilityLabel(L10n.shared.统计)
            .accessibilityIdentifier("topTabPicker")

            switch selectedTab {
            case .stats:
                StatsView()
            case .achievements:
                AchievementListView()
            }
        }
        // 左右滑动切换顶部「统计 / 成就」标签（与竖向滚动不冲突）
        .swipeToSwitchTab(
            onSwipeLeft: { moveOverviewTab(by: 1) },
            onSwipeRight: { moveOverviewTab(by: -1) }
        )
        // v1.3.4p：iPad 上 NavigationSplitView detail 内的 frame(maxWidth:) 失效，
        // 统计/列表在 iPad 保持自然宽度（参考邮件/备忘录 iPad 设计）
    }

    /// 按方向切换顶部标签（向左 = 下一个，向右 = 上一个），边界处夹紧不回环
    private func moveOverviewTab(by direction: Int) {
        let order = OverviewTab.allCases
        guard let idx = order.firstIndex(of: selectedTab) else { return }
        let newIdx = min(max(idx + direction, 0), order.count - 1)
        if newIdx != idx {
            selectedTab = order[newIdx]
        }
    }
}

#Preview {
    let l10nInstance = L10n.shared
    let notificationService = NotificationService()
    let focusService = FocusService(persistenceController: .shared, notificationService: notificationService)
    let statsVM = StatsViewModel(
        focusService: focusService,
        taskService: TaskService(persistenceController: .shared),
        persistenceController: .shared
    )
    let achievementVM = AchievementViewModel(
        achievementService: AchievementService(
            persistenceController: .shared
        ),
        persistenceController: .shared
    )
    StatsOverviewView()
        .environmentObject(l10nInstance)
        .environmentObject(statsVM)
        .environmentObject(achievementVM)
}

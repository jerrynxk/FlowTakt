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

            switch selectedTab {
            case .stats:
                StatsView()
            case .achievements:
                AchievementListView()
            }
        }
    }
}

#Preview {
    let l10nInstance = L10n.shared
    let notificationService1 = NotificationService()
    let notificationService2 = NotificationService()
    let focusService1 = FocusService(persistenceController: .shared, notificationService: notificationService1)
    let focusService2 = FocusService(persistenceController: .shared, notificationService: notificationService2)
    let statsVM = StatsViewModel(
        focusService: focusService1,
        taskService: TaskService(persistenceController: .shared),
        persistenceController: .shared
    )
    let achievementVM = AchievementViewModel(
        achievementService: AchievementService(
            persistenceController: .shared,
            focusService: focusService2
        )
    )
    return StatsOverviewView()
        .environmentObject(l10nInstance)
        .environmentObject(statsVM)
        .environmentObject(achievementVM)
}

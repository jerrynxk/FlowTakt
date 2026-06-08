import SwiftUI

// MARK: - 统计主视图

struct StatsView: View {
    @EnvironmentObject var statsViewModel: StatsViewModel
    @EnvironmentObject var taskViewModel: TaskViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    TodayOverviewCard()
                        .environmentObject(statsViewModel)

                    WeeklyChartView()
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
            .navigationTitle("统计")
            .refreshable {
                statsViewModel.refresh()
            }
        }
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

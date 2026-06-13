import SwiftUI

// MARK: - 计划视图（任务 + 日历）

struct PlanView: View {
    @EnvironmentObject var taskViewModel: TaskViewModel
    @EnvironmentObject var scheduleViewModel: ScheduleViewModel
    @EnvironmentObject var l10n: L10n

    @State private var selectedTab: PlanTab = .task

    enum PlanTab: CaseIterable {
        case task
        case calendar
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                ForEach(PlanTab.allCases, id: \.self) { tab in
                    switch tab {
                    case .task:     Text(L10n.shared.任务).tag(tab)
                    case .calendar: Text(L10n.shared.日程).tag(tab)
                    }
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            switch selectedTab {
            case .task:
                TaskListView()
            case .calendar:
                ScheduleView()
                    .environmentObject(taskViewModel)
            }
        }
    }
}

#Preview {
    PlanView()
        .environmentObject(TaskViewModel(
            taskService: TaskService(persistenceController: .shared),
            persistenceController: .shared
        ))
        .environmentObject(ScheduleViewModel(
            scheduleService: ScheduleService(persistenceController: .shared)
        ))
}

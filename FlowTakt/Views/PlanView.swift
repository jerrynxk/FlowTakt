import SwiftUI

// MARK: - 计划视图（任务 + 日历）

struct PlanView: View {
    @EnvironmentObject var taskViewModel: TaskViewModel
    @EnvironmentObject var scheduleViewModel: ScheduleViewModel
    @EnvironmentObject var l10n: L10n
    @EnvironmentObject var appDependency: AppDependency

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
                    .environmentObject(appDependency)
            }
        }
        // 消费来自 Widget 深链的待应用子页（如跳转到「日程」）
        .onReceive(appDependency.$pendingPlanTab) { pending in
            if let pending {
                selectedTab = pending
                appDependency.pendingPlanTab = nil
            }
        }
        // v1.3.4p：iPad 全量适配 — SwiftUI NavigationSplitView detail 内 frame(maxWidth:) 被撑开，
        // List/Picker 在 iPad 上保持自然宽度（参考邮件/备忘录的 iPad 设计）
    }
}

#Preview {
    PlanView()
        .environmentObject(TaskViewModel(
            taskService: TaskService(persistenceController: .shared),
            persistenceController: .shared
        ))
        .environmentObject(ScheduleViewModel(
            scheduleService: ScheduleService(persistenceController: .shared),
            persistenceController: .shared
        ))
        .environmentObject(AppDependency())
}

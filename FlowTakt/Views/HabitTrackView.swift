import SwiftUI

// MARK: - 习惯追踪视图（习惯 + 计时）

struct HabitTrackView: View {
    @EnvironmentObject var habitViewModel: HabitViewModel
    @EnvironmentObject var timeRecordViewModel: TimeRecordViewModel
    @EnvironmentObject var taskViewModel: TaskViewModel
    @EnvironmentObject var l10n: L10n

    @State private var selectedTab: TrackTab = .habit

    enum TrackTab: CaseIterable {
        case habit
        case timer
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                ForEach(TrackTab.allCases, id: \.self) { tab in
                    switch tab {
                    case .habit: return Text(L10n.shared.习惯).tag(tab)
                    case .timer:  return Text(L10n.shared.计时).tag(tab)
                    }
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            switch selectedTab {
            case .habit:
                HabitListView()
            case .timer:
                TimeRecordView()
                    .environmentObject(taskViewModel)
            }
        }
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

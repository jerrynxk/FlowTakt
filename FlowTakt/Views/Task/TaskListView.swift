import SwiftUI

// MARK: - TaskListView

struct TaskListView: View {
    @EnvironmentObject var taskViewModel: TaskViewModel
    @EnvironmentObject var l10n: L10n

    @State private var selectedTab: TaskTab = .active
    @State private var selectedPriority: Int16? = nil
    @State private var archiveSearch: String = ""
    /// 列表排序方式（组内排序；分组仍按日期）
    @State private var sortOption: TaskSortOption = .dueDate
    @EnvironmentObject var appDependency: AppDependency
    enum TaskTab: CaseIterable {
        case active
        case completed
        case archived

        var displayName: String {
            switch self {
            case .active:    return L10n.shared.已计划
            case .completed: return L10n.shared.已完成
            case .archived:  return L10n.shared.归档
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 分段控制器
                segmentedControl

                // 筛选栏 + 排序
                TaskFilterBar(selectedPriority: $selectedPriority)
                sortBar

                // 任务列表
                taskList
            }
            .background(Color.appBackground)
            .navigationTitle(L10n.shared.任务)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        taskViewModel.showCreateSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .fontWeight(.semibold)
                    }
                    .accessibilityLabel(L10n.shared.新建任务)
                }
            }
            .sheet(isPresented: $taskViewModel.showCreateSheet) {
                TaskCreateView()
                    .environmentObject(taskViewModel)
            }
            .navigationDestination(for: Task.self) { task in
                TaskDetailView(task: task)
                    .environmentObject(taskViewModel)
            }
            .searchable(text: $archiveSearch, prompt: L10n.shared.搜索归档任务)
            .onReceive(appDependency.$pendingTaskTab) { pending in
                if let pending, pending == "archived" {
                    selectedTab = .archived
                    appDependency.pendingTaskTab = nil
                }
            }
        }
    }

    // MARK: - Segmented Control

    private var segmentedControl: some View {
        Picker("", selection: $selectedTab) {
            ForEach(TaskTab.allCases, id: \.self) { tab in
                Text(tab.displayName).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    // MARK: - Sort Bar

    private var sortBar: some View {
        HStack {
            Text(L10n.shared.排序)
                .font(.caption)
                .foregroundColor(.secondary)
            Menu {
                ForEach(TaskSortOption.allCases) { option in
                    Button {
                        sortOption = option
                    } label: {
                        if sortOption == option {
                            Label(option.displayName, systemImage: "checkmark")
                        } else {
                            Text(option.displayName)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.caption)
                    Text(sortOption.displayName)
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.focusRed)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.focusRed.opacity(0.1)))
            }
            .accessibilityLabel(L10n.shared.排序)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 2)
    }

    // MARK: - Task List

    @ViewBuilder
    private var taskList: some View {
        let tasks = filteredTasks

        if tasks.isEmpty {
            emptyState
        } else {
            let grouped = groupTasksByDate(tasks)

            List {
                ForEach(grouped.keys.sorted(by: >), id: \.self) { dateKey in
                    if let tasksInSection = grouped[dateKey] {
                        Section {
                            // 组内按排序选项排列（默认截止日期）
                            ForEach(sort(tasksInSection)) { task in
                                NavigationLink(value: task) {
                                    TaskRowView(task: task)
                                }
                                .buttonStyle(.plain)
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    if task.status != TaskStatus.archived.rawValue {
                        Button {
                            withAnimation {
                                taskViewModel.archiveTask(task)
                            }
                        } label: {
                            Label(L10n.shared.归档, systemImage: "archivebox")
                        }
                        .tint(.orange)
                    }
                    leadingSwipeAction(for: task)
                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    trailingSwipeAction(for: task)
                                }
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            }
                        }                         header: {
                            if dateKey == Date.distantPast {
                                HStack(spacing: 6) {
                                    Image(systemName: "calendar.badge.minus")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(selectedTab == .active ? L10n.shared.未设定日期 : L10n.shared.未记录时间)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.primary)
                                    Spacer()
                                }
                                .padding(.horizontal, 4)
                                .padding(.vertical, 6)
                                .background(Color(.systemGroupedBackground))
                            } else {
                                DateSectionHeader(date: dateKey)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: - Filtered Tasks

    private var filteredTasks: [Task] {
        let source: [Task]
        switch selectedTab {
        case .active:
            source = taskViewModel.activeTasks
        case .completed:
            source = taskViewModel.completedTasks
        case .archived:
            source = taskViewModel.archivedTasks
        }

        var result = source
        if selectedTab == .archived, !archiveSearch.isEmpty {
            result = result.filter { $0.title.localizedCaseInsensitiveContains(archiveSearch) }
        }
        if let priority = selectedPriority {
            result = result.filter { $0.priority == priority }
        }
        return result
    }

    /// 按排序选项对任务排序（经 TaskViewModel 静态方法，逻辑可单测）
    private func sort(_ tasks: [Task]) -> [Task] {
        TaskViewModel.sortTasks(tasks, by: sortOption)
    }

    // MARK: - Grouping

    private func groupTasksByDate(_ tasks: [Task]) -> [Date: [Task]] {
        var grouped: [Date: [Task]] = [:]

        for task in tasks {
            let key: Date
            switch selectedTab {
            case .active:
                key = task.dueDate?.startOfDay ?? Date.distantPast
            case .completed:
                key = task.completedAt?.startOfDay ?? Date.distantPast
            case .archived:
                key = task.updatedAt.startOfDay
            }
            var section = grouped[key] ?? []
            section.append(task)
            grouped[key] = section
        }

        return grouped
    }

    // MARK: - Swipe Actions

    @ViewBuilder
    private func leadingSwipeAction(for task: Task) -> some View {
        if task.status == TaskStatus.archived.rawValue {
            Button {
                withAnimation {
                    taskViewModel.reactivateTask(task)
                }
            } label: {
                Label(L10n.shared.恢复, systemImage: "arrow.uturn.backward")
            }
            .tint(.blue)
        } else if task.isCompleted {
            Button {
                withAnimation {
                    taskViewModel.reactivateTask(task)
                }
            } label: {
                Label(L10n.shared.恢复, systemImage: "arrow.uturn.backward")
            }
            .tint(.blue)
        } else {
            Button {
                withAnimation {
                    taskViewModel.completeTask(task)
                }
            } label: {
                Label(L10n.shared.完成, systemImage: "checkmark.circle.fill")
            }
            .tint(.green)
        }
    }

    @ViewBuilder
    private func trailingSwipeAction(for task: Task) -> some View {
                    Button(role: .destructive) {
                        withAnimation {
                            taskViewModel.deleteTask(task)
                        }
                    } label: {
                        Label(L10n.shared.删除, systemImage: "trash")
                    }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: emptyIcon)
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))

            Text(emptyTitle)
                .font(.title3)
                .fontWeight(.medium)
                .foregroundColor(.secondary)

            Text(emptySubtitle)
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            if selectedTab == .active {
                Button {
                    taskViewModel.showCreateSheet = true
                } label: {
                    Label(L10n.shared.创建第一个任务, systemImage: "plus.circle.fill")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .tint(.focusRed)
                .padding(.top, 4)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyIcon: String {
        switch selectedTab {
        case .active:
            return "checklist"
        case .completed:
            return "checkmark.circle"
        case .archived:
            return "archivebox"
        }
    }

    private var emptyTitle: String {
        switch selectedTab {
        case .active:
            return L10n.shared.noTasks
        case .completed:
            return L10n.shared.noCompletedTasks
        case .archived:
            return L10n.shared.暂无归档任务
        }
    }

    private var emptySubtitle: String {
        switch selectedTab {
        case .active:
            return L10n.shared.createFirstTask
        case .completed:
            return L10n.shared.completedWillShowHere
        case .archived:
            return L10n.shared.归档任务为空说明
        }
    }
}

// MARK: - Preview

#Preview {
    TaskListView()
        .environmentObject(AppDependency().taskViewModel)
}

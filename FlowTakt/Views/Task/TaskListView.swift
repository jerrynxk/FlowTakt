import SwiftUI

// MARK: - TaskListView

struct TaskListView: View {
    @EnvironmentObject var taskViewModel: TaskViewModel
    @EnvironmentObject var l10n: L10n

    @State private var selectedTab: TaskTab = .active
    @State private var selectedPriority: Int16? = nil
    enum TaskTab: CaseIterable {
        case active
        case completed

        var displayName: String {
            switch self {
            case .active:    return L10n.shared.已计划
            case .completed: return L10n.shared.已完成
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 分段控制器
                segmentedControl

                // 筛选栏
                TaskFilterBar(selectedPriority: $selectedPriority)

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
                            ForEach(tasksInSection) { task in
                                NavigationLink(value: task) {
                                    TaskRowView(task: task)
                                }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
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
        }

        if let priority = selectedPriority {
            return source.filter { $0.priority == priority }
        }
        return source
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
        if task.isCompleted {
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
        }
    }

    private var emptyTitle: String {
        switch selectedTab {
        case .active:
            return L10n.shared.noTasks
        case .completed:
            return L10n.shared.noCompletedTasks
        }
    }

    private var emptySubtitle: String {
        switch selectedTab {
        case .active:
            return L10n.shared.createFirstTask
        case .completed:
            return L10n.shared.completedWillShowHere
        }
    }
}

// MARK: - Preview

#Preview {
    TaskListView()
        .environmentObject(AppDependency().taskViewModel)
}

import SwiftUI

// MARK: - TaskListView

struct TaskListView: View {
    @EnvironmentObject var taskViewModel: TaskViewModel
    @EnvironmentObject var l10n: L10n

    // 修复（2026-10-15 审查 P1-016）：页签选择持久化到 UserDefaults——
    // 此前是纯 View 局部状态，深链/重启后回落到「已计划」；现与深链写入路径共存：
    // onAppear 恢复 + onChange 持久化，onReceive 深链覆盖仍优先生效。
    @State private var selectedTab: TaskTab = .active
    @State private var selectedPriority: Int16? = nil
    @State private var archiveSearch: String = ""
    /// 列表排序方式（组内排序；分组仍按日期）
    @State private var sortOption: TaskSortOption = .dueDate
    @EnvironmentObject var appDependency: AppDependency
    enum TaskTab: String, CaseIterable {
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

    /// 页签持久化键（跨启动记忆用户停留的分组）
    private static let selectedTabKey = "taskListSelectedTab"

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 标题行：「任务」标题与「+」新建按钮并排一行，紧贴顶部分段控件（2026-10-14）
                // 原先「+」挂在导航栏 primaryAction、大标题由 .large 模式渲染，
                // 两者上下分离且搜索框被夹在中间，视觉割裂。这里改为内容区自绘标题行。
                //
                // 关键：导航栏已整体隐藏（见下方 .toolbar(.hidden)）。
                // 否则导航栏会占掉约 44pt 高度，在「任务/日程」分段控件与标题行之间
                // 留下一条空档；同时 .searchable 也依赖导航栏，故搜索框一并改为自绘
                // （见 searchField），使其能够排在标题行之下。
                titleRow

                // 搜索框（内容区自绘，取代原 .searchable）
                // 修复（2026-10-14 P2）：搜索只对归档列表生效（archiveSearch），此前三个页签
            // 恒显示搜索框但在「已计划 / 已完成」输入任何文字都无反应，属明显的假交互。
            if selectedTab == .archived { searchField }

                // 分段控制器（已计划 / 已完成 / 归档）
                segmentedControl

                // 筛选栏 + 排序
                TaskFilterBar(selectedPriority: $selectedPriority)
                sortBar

                // 任务列表
                taskList
            }
            .background(Color.appBackground)
            // 隐藏导航栏，标题行得以成为内容首项、紧贴顶部分段控件。
            // 仍保留 navigationTitle 以便 push 到任务详情页时返回按钮显示「任务」。
            .navigationTitle(L10n.shared.任务)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $taskViewModel.showCreateSheet) {
                TaskCreateView()
                    .environmentObject(taskViewModel)
            }
            .navigationDestination(for: Task.self) { task in
                TaskDetailView(task: task)
                    .environmentObject(taskViewModel)
            }
            // 注：原 `.searchable` 已移除（它依赖导航栏且会把内容首行下推）。
            //     搜索框改由内容区自绘，见 `searchField`。
            .onReceive(appDependency.$pendingTaskTab) { pending in
                if let pending, pending == "archived" {
                    selectedTab = .archived
                    appDependency.pendingTaskTab = nil
                }
            }
            .onAppear {
                // 恢复上次的页签选择（深链场景 onReceive 会随后覆盖）
                if let raw = UserDefaults.standard.string(forKey: Self.selectedTabKey),
                   let tab = TaskTab(rawValue: raw) {
                    selectedTab = tab
                }
            }
            .onChange(of: selectedTab) { _, new in
                UserDefaults.standard.set(new.rawValue, forKey: Self.selectedTabKey)
            }
        }
    }

    // MARK: - Search Field

    /// 内容区自绘搜索框（2026-10-14 取代系统 `.searchable`）。
    ///
    /// 替换理由：`.searchable` 的搜索框由导航栏承载，会占掉约 44pt 导航栏高度，
    /// 使「任务」标题行无法紧贴顶部分段控件，中间留下一条空档。
    /// 自绘后标题行成为内容首项，层级为「标题行 → 搜索框 → 分段控件 → 筛选栏」。
    /// 视觉规格对齐系统搜索框：圆角 10、systemGray6 底、放大镜图标、可清除。
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.body)
                .foregroundColor(.secondary)
                .accessibilityHidden(true)

            TextField(L10n.shared.搜索归档任务, text: $archiveSearch)
                .font(.body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)

            if !archiveSearch.isEmpty {
                Button {
                    archiveSearch = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.shared.清除搜索内容)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.systemGray6))
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Title Row

    /// 标题行：「任务」大标题 + 「+」新建按钮（同一行）
    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(L10n.shared.任务)
                .font(.largeTitle.weight(.bold))
                // 无障碍（2026-10-14）：大标题标记为一级标题（VoiceOver 转子可按标题跳转）
                .accessibilityHeading(.h1)
            Spacer(minLength: 12)
            Button {
                taskViewModel.showCreateSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.focusRed)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.shared.新建任务)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 4)
    }

    private var segmentedControl: some View {
        Picker("", selection: $selectedTab) {
            ForEach(TaskTab.allCases, id: \.self) { tab in
                Text(tab.displayName).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        // 修复（2026-10-14 审查 P2-40）：分段控件补用途标签，
        // 与今日已补的阶段/计划/习惯/统计四处保持同一无障碍约定
        .accessibilityLabel(L10n.shared.任务)
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
            .accessibilityLabel(L10n.shared.排序 + "：" + sortOption.displayName)
            // 无障碍补齐（2026-11-02）：label 现在含当前排序值（读屏可判断当前排序方式），
            // 因此 UI 测试不再按文案精确匹配，改用稳定标识定位
            .accessibilityIdentifier("sortMenu")
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
                                        // 无障碍补齐（2026-11-02）：装饰图标不单独朗读
                                        .accessibilityHidden(true)
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
            // 滚动统一调整（2026-11-02）：与其它页面一致地禁用弹性 + 柔化撞停减速
            .disableBounce()
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
                // 无障碍（2026-10-14）：空状态装饰图标不单独朗读（下方文案已说明）
                .accessibilityHidden(true)

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
        .environmentObject(L10n.shared)
}

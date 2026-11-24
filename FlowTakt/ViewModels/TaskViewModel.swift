import Foundation
import Combine
import CoreData

// MARK: - 任务排序选项（A3）

enum TaskSortOption: String, CaseIterable, Identifiable {
    case dueDate
    case priority
    case createdAt

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dueDate:   return L10n.shared.按截止日期
        case .priority:  return L10n.shared.按优先级
        case .createdAt: return L10n.shared.按创建时间
        }
    }
}

// MARK: - TaskViewModel

final class TaskViewModel: ObservableObject {
    // MARK: - Dependencies

    private let taskService: TaskServiceProtocol
    private let persistenceController: PersistenceController

    private var viewContext: NSManagedObjectContext {
        persistenceController.viewContext
    }

    // MARK: - Published Properties

    /// 所有任务
    @Published var tasks: [Task] = []
    /// 活跃任务（进行中）
    @Published var activeTasks: [Task] = []
    /// 已完成任务
    @Published var completedTasks: [Task] = []
    /// 已归档任务（隐藏但保留，可检索/恢复）
    @Published var archivedTasks: [Task] = []
    /// 是否显示创建任务表单
    @Published var showCreateSheet: Bool = false
    /// 正在编辑的任务（nil 表示新建）
    @Published var editingTask: Task? = nil

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init(taskService: TaskServiceProtocol, persistenceController: PersistenceController) {
        self.taskService = taskService
        self.persistenceController = persistenceController

        // 初始化时加载数据
        loadTasks()

        // 监听 CoreData 上下文变化，自动刷新
        NotificationCenter.default.publisher(
            for: .NSManagedObjectContextObjectsDidChange,
            object: viewContext
        )
        .receive(on: DispatchQueue.main)
        .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.loadTasks()
        }
        .store(in: &cancellables)

        // 监听数据库重置通知，立即清空旧 ManagedObject 引用防止崩溃
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDatabaseWillReset),
            name: .databaseWillReset,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDatabaseDidReset),
            name: .databaseDidReset,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Private

    @objc private func handleDatabaseWillReset() {
        // 立即清空已删除的 ManagedObject 引用
        tasks = []
        activeTasks = []
        completedTasks = []
        archivedTasks = []
        editingTask = nil
    }

    @objc private func handleDatabaseDidReset() {
        // 异步重新加载
        DispatchQueue.main.async { [weak self] in
            self?.loadTasks()
        }
    }

    // MARK: - Public Methods

    /// 加载所有任务并分类（审查 #12：一次全量拉取后内存分组，替代 4 次全表查询）
    func loadTasks() {
        tasks = taskService.fetchAllTasks()
        activeTasks = tasks.filter { $0.status == TaskStatus.active.rawValue }
        completedTasks = tasks.filter { $0.status == TaskStatus.completed.rawValue }
        archivedTasks = tasks.filter { $0.status == TaskStatus.archived.rawValue }
    }

    /// 按排序选项对任务排序（稳定排序，无截止日期的排最后）
    static func sortTasks(_ tasks: [Task], by option: TaskSortOption) -> [Task] {
        switch option {
        case .dueDate:
            // 审查 #19：次级按创建时间降序保证确定性（避免同截止日期任务顺序抖动）
            return tasks.sorted { lhs, rhs in
                let l = lhs.dueDate ?? .distantFuture
                let r = rhs.dueDate ?? .distantFuture
                if l != r { return l < r }
                return lhs.createdAt > rhs.createdAt
            }
        case .priority:
            // 审查修复（2026-08-12）：优先级相同时按创建时间降序，避免同级任务顺序抖动
            return tasks.sorted { lhs, rhs in
                if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
                return lhs.createdAt > rhs.createdAt
            }
        case .createdAt:
            return tasks.sorted { $0.createdAt > $1.createdAt }
        }
    }

    /// 创建新任务
    /// - Parameters:
    ///   - title: 任务标题
    ///   - notes: 备注（可选）
    ///   - estimatedPomodoros: 预计需要几个番茄钟
    ///   - priority: 优先级（1=低, 2=中, 3=高）
    ///   - dueDate: 截止日期（可选）
    @discardableResult
    func createTask(title: String, notes: String?, estimatedPomodoros: Int16, priority: Int16, dueDate: Date?, recurrenceRule: String? = nil) -> Task? {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }

        let newTask = taskService.createTask(
            title: title,
            notes: notes,
            estimatedPomodoros: estimatedPomodoros,
            priority: priority,
            dueDate: dueDate,
            recurrenceRule: recurrenceRule
        )

        loadTasks()
        showCreateSheet = false
        return newTask
    }

    /// 更新任务（通过 Service 层，避免 View 直接修改 NSManagedObject）
    /// - Parameters:
    ///   - task: 要更新的任务
    ///   - title: 新标题
    ///   - notes: 新备注
    ///   - estimatedPomodoros: 预计番茄数
    ///   - priority: 优先级
    ///   - dueDate: 截止日期
    func updateTask(_ task: Task, title: String, notes: String?, estimatedPomodoros: Int16, priority: Int16, dueDate: Date?) {
        taskService.updateTask(
            task,
            title: title,
            notes: notes,
            estimatedPomodoros: estimatedPomodoros,
            priority: priority,
            status: nil,
            dueDate: dueDate
        )
        loadTasks()
    }

    /// 删除任务
    /// - Parameter task: 要删除的任务
    func deleteTask(_ task: Task) {
        // 触觉反馈：删除为破坏性操作，用中度反馈提示
        HapticManager.shared.mediumImpact()
        taskService.deleteTask(task)
        loadTasks()
    }

    /// 标记任务为已完成
    /// - Parameter task: 要完成的任务
    func completeTask(_ task: Task) {
        // 触觉反馈：完成（轻量选择反馈）
        HapticManager.shared.selectionFeedback()
        taskService.updateTask(
            task,
            title: nil,
            notes: nil,
            estimatedPomodoros: nil,
            priority: nil,
            status: TaskStatus.completed.rawValue,
            dueDate: nil
        )
        loadTasks()
    }

    /// 重新激活已完成/已归档的任务
    /// - Parameter task: 要激活的任务
    func reactivateTask(_ task: Task) {
        // 触觉反馈：恢复
        HapticManager.shared.selectionFeedback()
        taskService.updateTask(
            task,
            title: nil,
            notes: nil,
            estimatedPomodoros: nil,
            priority: nil,
            status: TaskStatus.active.rawValue,
            dueDate: nil
        )
        loadTasks()
    }

    /// 归档任务（隐藏但保留，可从归档分段恢复）
    /// - Parameter task: 要归档的任务
    func archiveTask(_ task: Task) {
        // 触觉反馈：归档
        HapticManager.shared.selectionFeedback()
        taskService.updateTask(
            task,
            title: nil,
            notes: nil,
            estimatedPomodoros: nil,
            priority: nil,
            status: TaskStatus.archived.rawValue,
            dueDate: nil
        )
        loadTasks()
    }
}

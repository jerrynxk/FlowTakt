import Foundation
import Combine
import CoreData

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
        .sink { [weak self] _ in
            self?.loadTasks()
        }
        .store(in: &cancellables)
    }

    // MARK: - Public Methods

    /// 加载所有任务并分类
    func loadTasks() {
        tasks = taskService.fetchAllTasks()
        activeTasks = taskService.fetchActiveTasks()
        completedTasks = taskService.fetchCompletedTasks()
    }

    /// 创建新任务
    /// - Parameters:
    ///   - title: 任务标题
    ///   - notes: 备注（可选）
    ///   - estimatedPomodoros: 预计需要几个番茄钟
    ///   - priority: 优先级（1=低, 2=中, 3=高）
    ///   - dueDate: 截止日期（可选）
    func createTask(title: String, notes: String?, estimatedPomodoros: Int16, priority: Int16, dueDate: Date?) {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        _ = taskService.createTask(
            title: title,
            notes: notes,
            estimatedPomodoros: estimatedPomodoros,
            priority: priority,
            dueDate: dueDate
        )

        loadTasks()
        showCreateSheet = false
    }

    /// 刷新任务（重新加载列表）
    /// - Parameter task: 要刷新的任务
    func refreshTask(_ task: Task) {
        taskService.updateTask(
            task,
            title: nil,
            notes: nil,
            estimatedPomodoros: nil,
            priority: nil,
            status: nil,
            dueDate: nil
        )
        loadTasks()
    }

    /// 删除任务
    /// - Parameter task: 要删除的任务
    func deleteTask(_ task: Task) {
        taskService.deleteTask(task)
        loadTasks()
    }

    /// 标记任务为已完成
    /// - Parameter task: 要完成的任务
    func completeTask(_ task: Task) {
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
}

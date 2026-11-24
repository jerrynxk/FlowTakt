import Foundation
@preconcurrency import CoreData

// MARK: - TaskService 协议

protocol TaskServiceProtocol {
    func createTask(title: String, notes: String?, estimatedPomodoros: Int16, priority: Int16, dueDate: Date?, recurrenceRule: String?) -> Task
    func updateTask(_ task: Task, title: String?, notes: String?, estimatedPomodoros: Int16?, priority: Int16?, status: String?, dueDate: Date?, recurrenceRule: String?)
    func deleteTask(_ task: Task)
    func fetchAllTasks() -> [Task]
    func fetchActiveTasks() -> [Task]
    func fetchCompletedTasks() -> [Task]
    func fetchArchivedTasks() -> [Task]
    func incrementCompletedPomodoros(for task: Task)
}

// MARK: - TaskServiceProtocol 默认实现
// 提供带默认参数的便捷方法，转发到协议主方法。具体类型必须实现主方法。

extension TaskServiceProtocol {
    func createTask(title: String, notes: String?, estimatedPomodoros: Int16, priority: Int16, dueDate: Date?, recurrenceRule: String? = nil) -> Task {
        createTask(title: title, notes: notes, estimatedPomodoros: estimatedPomodoros, priority: priority, dueDate: dueDate, recurrenceRule: recurrenceRule)
    }

    func updateTask(_ task: Task, title: String? = nil, notes: String? = nil, estimatedPomodoros: Int16? = nil, priority: Int16? = nil, status: String? = nil, dueDate: Date? = nil, recurrenceRule: String? = nil) {
        updateTask(task, title: title, notes: notes, estimatedPomodoros: estimatedPomodoros, priority: priority, status: status, dueDate: dueDate, recurrenceRule: recurrenceRule)
    }
}

// MARK: - 任务服务实现

@MainActor
final class TaskService: TaskServiceProtocol {
    private let persistenceController: PersistenceController

    /// 错误回调：供 ViewModel 层监听 Service 内部错误
    var onError: ((Error) -> Void)?

    private var viewContext: NSManagedObjectContext {
        persistenceController.viewContext
    }
    /// save 失败统一上报（判据收口，2026-10-15 审查 P1-001）：
    /// 所有写路径经此检查，store 未就绪/保存失败时不再静默丢弃。
    func saveAndReport() {
        if !persistenceController.save() {
            onError?(AppError.coreDataSaveFailed(NSError(domain: "FlowTakt.TaskService",
                                                         code: NSFileWriteUnknownError)))
        }
    }

    init(persistenceController: PersistenceController) {
        self.persistenceController = persistenceController
    }

    func createTask(title: String, notes: String?, estimatedPomodoros: Int16, priority: Int16, dueDate: Date?, recurrenceRule: String? = nil) -> Task {
        let task = Task(context: viewContext)
        task.storageId = UUID()
        task.title = title
        task.notes = notes
        task.estimatedPomodoros = estimatedPomodoros
        task.completedPomodoros = 0
        task.priority = priority
        task.status = TaskStatus.active.rawValue
        task.dueDate = dueDate
        // 设置重复规则
        if let rule = recurrenceRule, rule != "none" {
            task.isRecurring = true
            task.recurrenceRule = rule
        }
        // 计算下一个可用的 displayOrder：在已有任务中取最大值 + 1，避免删除旧任务后重复
        // 崩溃修复（2026-10-15 审查 P0-2）：try? 捕获不了 ObjC 异常，store 未就绪须先短路
        var maxOrder: Int16 = -1
        if persistenceController.canFetchSafely("TaskService.createTask.displayOrder") {
            let orderRequest = Task.fetchRequest()
            orderRequest.includesPendingChanges = false
            orderRequest.fetchLimit = 1
            orderRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Task.displayOrder, ascending: false)]
            maxOrder = (try? viewContext.fetch(orderRequest).first?.displayOrder) ?? -1
        }
        task.displayOrder = maxOrder + 1
        task.createdAt = Date()
        task.updatedAt = Date()
        saveAndReport()
        return task
    }

    func updateTask(_ task: Task, title: String? = nil, notes: String? = nil, estimatedPomodoros: Int16? = nil, priority: Int16? = nil, status: String? = nil, dueDate: Date? = nil, recurrenceRule: String? = nil) {
        if let title = title { task.title = title }
        if let notes = notes { task.notes = notes }
        if let estimatedPomodoros = estimatedPomodoros { task.estimatedPomodoros = estimatedPomodoros }
        if let priority = priority { task.priority = priority }
        if let status = status { task.status = status }
        if let dueDate = dueDate { task.dueDate = dueDate }
        if let rule = recurrenceRule {
            task.recurrenceRule = rule
            task.isRecurring = (rule != "none")
        }

        task.updatedAt = Date()

        if status == TaskStatus.completed.rawValue {
            task.completedAt = Date()
            // 处理重复任务：自动创建下一个实例
            handleRecurringTaskCompletion(task)
        }
        saveAndReport()
    }

    func deleteTask(_ task: Task) {
        // 修复（2026-10-14 审查 P0-2）：数据模型中 `Task.sessions` 的删除规则是 **Cascade**，
        // 直接删任务会连带删除该任务的**全部专注历史**，包括正在运行的那一条 ——
        // 专注页 `currentSession` 变成悬垂引用，计时结束/暂停/恢复时读已删对象属未定义行为
        // （可能触发 CoreData fault 异常崩溃），且该番茄记录凭空消失。
        // 先把会话的 task 置 nil，使删除退化为 Nullify 语义：任务删除、专注历史保留。
        let now = Date()
        for session in task.sessions {
            session.task = nil
            session.updatedAt = now
        }
        viewContext.delete(task)
        saveAndReport()
    }

    func fetchAllTasks() -> [Task] {
        guard persistenceController.canFetchSafely("TaskService.fetchAllTasks") else { return [] }
        let request = Task.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Task.displayOrder, ascending: true)]
        do {
            return try viewContext.fetch(request)
        } catch {
            print("获取任务列表失败：\(error.localizedDescription)")
            onError?(error)
            return []
        }
    }

    func fetchActiveTasks() -> [Task] {
        guard persistenceController.canFetchSafely("TaskService.fetchActiveTasks") else { return [] }
        let request = Task.fetchRequest()
        request.predicate = NSPredicate(format: "status == %@", TaskStatus.active.rawValue)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Task.displayOrder, ascending: true)]
        do {
            return try viewContext.fetch(request)
        } catch {
            print("获取活跃任务失败：\(error.localizedDescription)")
            onError?(error)
            return []
        }
    }

    func fetchCompletedTasks() -> [Task] {
        guard persistenceController.canFetchSafely("TaskService.fetchCompletedTasks") else { return [] }
        let request = Task.fetchRequest()
        request.predicate = NSPredicate(format: "status == %@", TaskStatus.completed.rawValue)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Task.updatedAt, ascending: false)]
        do {
            return try viewContext.fetch(request)
        } catch {
            print("获取已完成任务失败：\(error.localizedDescription)")
            onError?(error)
            return []
        }
    }

    func fetchArchivedTasks() -> [Task] {
        guard persistenceController.canFetchSafely("TaskService.fetchArchivedTasks") else { return [] }
        let request = Task.fetchRequest()
        request.predicate = NSPredicate(format: "status == %@", TaskStatus.archived.rawValue)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Task.updatedAt, ascending: false)]
        do {
            return try viewContext.fetch(request)
        } catch {
            print("获取归档任务失败：\(error.localizedDescription)")
            onError?(error)
            return []
        }
    }

    func incrementCompletedPomodoros(for task: Task) {
        task.completedPomodoros += 1
        task.updatedAt = Date()
        saveAndReport()
    }

    // MARK: - 重复任务处理

    /// 完成重复任务时，自动创建下一个实例
    private func handleRecurringTaskCompletion(_ task: Task) {
        guard task.isRecurring, let rule = task.recurrenceRule else { return }

        // 幂等：若已存在同标题的 active 实例（完成→重新激活→再完成等重复操作），不再创建，
        // 避免同一条重复任务生成多个并列的下一实例
        // 崩溃修复（2026-10-15 审查 P0-2）：try? 捕获不了 ObjC 异常，store 未就绪时跳过创建
        guard persistenceController.canFetchSafely("TaskService.handleRecurringTaskCompletion") else { return }
        let existingRequest = Task.fetchRequest()
        existingRequest.predicate = NSPredicate(
            format: "title == %@ AND status == %@",
            task.title, TaskStatus.active.rawValue
        )
        existingRequest.fetchLimit = 1
        if let existing = try? viewContext.fetch(existingRequest), !existing.isEmpty {
            return
        }

        // 检查是否超过重复截止日期
        if let endDate = task.recurrenceEndDate, Date() > endDate {
            return
        }

        // 计算下一个截止日期
        let nextDueDate: Date? = {
            guard let currentDue = task.dueDate else {
                // 如果没有截止日期，以当前时间为基准
                return nextDate(from: Date(), rule: rule)
            }
            return nextDate(from: currentDue, rule: rule)
        }()

        // 创建同标题的下一个任务实例
        let nextTask = Task(context: viewContext)
        nextTask.storageId = UUID()
        nextTask.title = task.title
        nextTask.notes = task.notes
        nextTask.estimatedPomodoros = task.estimatedPomodoros
        nextTask.completedPomodoros = 0
        nextTask.priority = task.priority
        nextTask.status = TaskStatus.active.rawValue
        nextTask.dueDate = nextDueDate
        nextTask.isRecurring = true
        nextTask.recurrenceRule = rule
        nextTask.recurrenceEndDate = task.recurrenceEndDate
        // 复制标签关系（避免重复任务丢失分类）
        nextTask.tags = task.tags
        // 继承父任务关系（2026-10-15 审查 P2-D3）：否则子任务生成的下一实例会
        // 变成顶层任务，子任务链表断裂、与原任务结构不一致
        nextTask.parentTask = task.parentTask
        // displayOrder 设为已完成任务 displayOrder + 1，避免排序值冲突
        nextTask.displayOrder = task.displayOrder + 1
        nextTask.createdAt = Date()
        nextTask.updatedAt = Date()
        // 显式保存，确保重复任务的下一实例被持久化
        saveAndReport()
    }

    /// 根据重复规则计算下一个日期
    private func nextDate(from date: Date, rule: String) -> Date? {
        let calendar = Calendar.current
        switch rule {
        case "daily":
            return calendar.date(byAdding: .day, value: 1, to: date)
        case "weekly":
            return calendar.date(byAdding: .weekOfYear, value: 1, to: date)
        case "biweekly":
            return calendar.date(byAdding: .weekOfYear, value: 2, to: date)
        case "monthly":
            return calendar.date(byAdding: .month, value: 1, to: date)
        case "yearly":
            return calendar.date(byAdding: .year, value: 1, to: date)
        case "weekday":
            // 下一个工作日（跳过周末）
            var result = calendar.date(byAdding: .day, value: 1, to: date) ?? date
            let weekday = calendar.component(.weekday, from: result)
            if weekday == 7 { // 周六 → 下周一
                result = calendar.date(byAdding: .day, value: 2, to: result) ?? result
            } else if weekday == 1 { // 周日 → 周一
                result = calendar.date(byAdding: .day, value: 1, to: result) ?? result
            }
            return result
        default:
            return nil
        }
    }
}

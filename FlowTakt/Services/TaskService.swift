import Foundation
import CoreData

// MARK: - TaskService 协议

protocol TaskServiceProtocol {
    func createTask(title: String, notes: String?, estimatedPomodoros: Int16, priority: Int16, dueDate: Date?, recurrenceRule: String?) -> Task
    func updateTask(_ task: Task, title: String?, notes: String?, estimatedPomodoros: Int16?, priority: Int16?, status: String?, dueDate: Date?, recurrenceRule: String?)
    func deleteTask(_ task: Task)
    func fetchAllTasks() -> [Task]
    func fetchActiveTasks() -> [Task]
    func fetchCompletedTasks() -> [Task]
    func incrementCompletedPomodoros(for task: Task)
}

// MARK: - TaskServiceProtocol 默认实现

extension TaskServiceProtocol {
    func createTask(title: String, notes: String?, estimatedPomodoros: Int16, priority: Int16, dueDate: Date?, recurrenceRule: String? = nil) -> Task {
        createTask(title: title, notes: notes, estimatedPomodoros: estimatedPomodoros, priority: priority, dueDate: dueDate, recurrenceRule: recurrenceRule)
    }

    func updateTask(_ task: Task, title: String? = nil, notes: String? = nil, estimatedPomodoros: Int16? = nil, priority: Int16? = nil, status: String? = nil, dueDate: Date? = nil, recurrenceRule: String? = nil) {
        updateTask(task, title: title, notes: notes, estimatedPomodoros: estimatedPomodoros, priority: priority, status: status, dueDate: dueDate, recurrenceRule: recurrenceRule)
    }
}

// MARK: - 任务服务实现

final class TaskService: TaskServiceProtocol {
    private let persistenceController: PersistenceController

    /// 错误回调：供 ViewModel 层监听 Service 内部错误
    var onError: ((Error) -> Void)?

    private var viewContext: NSManagedObjectContext {
        persistenceController.viewContext
    }

    init(persistenceController: PersistenceController) {
        self.persistenceController = persistenceController
    }

    func createTask(title: String, notes: String?, estimatedPomodoros: Int16, priority: Int16, dueDate: Date?, recurrenceRule: String? = nil) -> Task {
        let task = Task(context: viewContext)
        task.id = UUID()
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
        let orderRequest = Task.fetchRequest()
        orderRequest.includesPendingChanges = false
        orderRequest.fetchLimit = 1
        orderRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Task.displayOrder, ascending: false)]
        let maxOrder = (try? viewContext.fetch(orderRequest).first?.displayOrder) ?? -1
        task.displayOrder = maxOrder + 1
        task.createdAt = Date()
        task.updatedAt = Date()
        persistenceController.save()
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
        persistenceController.save()
    }

    func deleteTask(_ task: Task) {
        viewContext.delete(task)
        persistenceController.save()
    }

    func fetchAllTasks() -> [Task] {
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

    func incrementCompletedPomodoros(for task: Task) {
        task.completedPomodoros += 1
        task.updatedAt = Date()
        persistenceController.save()
    }

    // MARK: - 重复任务处理

    /// 完成重复任务时，自动创建下一个实例
    private func handleRecurringTaskCompletion(_ task: Task) {
        viewContext.performAndWait {
            guard task.isRecurring, let rule = task.recurrenceRule else { return }

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
            nextTask.id = UUID()
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
            // displayOrder 设为已完成任务 displayOrder + 1，避免排序值冲突
            nextTask.displayOrder = task.displayOrder + 1
            nextTask.createdAt = Date()
            nextTask.updatedAt = Date()
            // 显式保存，确保重复任务的下一实例被持久化
            persistenceController.save()
        }
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

import Foundation
import CoreData

// MARK: - TaskService 协议

protocol TaskServiceProtocol {
    func createTask(title: String, notes: String?, estimatedPomodoros: Int16, priority: Int16, dueDate: Date?) -> Task
    func updateTask(_ task: Task, title: String?, notes: String?, estimatedPomodoros: Int16?, priority: Int16?, status: String?, dueDate: Date?)
    func deleteTask(_ task: Task)
    func fetchAllTasks() -> [Task]
    func fetchActiveTasks() -> [Task]
    func fetchCompletedTasks() -> [Task]
    func incrementCompletedPomodoros(for task: Task)
}

// MARK: - 任务服务实现

final class TaskService: TaskServiceProtocol {
    private let persistenceController: PersistenceController

    private var viewContext: NSManagedObjectContext {
        persistenceController.viewContext
    }

    init(persistenceController: PersistenceController) {
        self.persistenceController = persistenceController
    }

    func createTask(title: String, notes: String?, estimatedPomodoros: Int16, priority: Int16, dueDate: Date?) -> Task {
        let task = Task(context: viewContext)
        task.id = UUID()
        task.title = title
        task.notes = notes
        task.estimatedPomodoros = estimatedPomodoros
        task.completedPomodoros = 0
        task.priority = priority
        task.status = TaskStatus.active.rawValue
        task.dueDate = dueDate
        task.displayOrder = Int16(max(0, fetchAllTasks().count - 1))
        task.createdAt = Date()
        task.updatedAt = Date()
        persistenceController.save()
        return task
    }

    func updateTask(_ task: Task, title: String? = nil, notes: String? = nil, estimatedPomodoros: Int16? = nil, priority: Int16? = nil, status: String? = nil, dueDate: Date? = nil) {
        if let title = title { task.title = title }
        if let notes = notes { task.notes = notes }
        if let estimatedPomodoros = estimatedPomodoros { task.estimatedPomodoros = estimatedPomodoros }
        if let priority = priority { task.priority = priority }
        if let status = status { task.status = status }
        if let dueDate = dueDate { task.dueDate = dueDate }
        task.updatedAt = Date()

        if status == TaskStatus.completed.rawValue {
            task.completedAt = Date()
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
            return []
        }
    }

    func incrementCompletedPomodoros(for task: Task) {
        task.completedPomodoros += 1
        task.updatedAt = Date()
        persistenceController.save()
    }
}

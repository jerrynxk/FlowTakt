import XCTest
import CoreData
import Combine
@testable import FlowTakt

// MARK: - TaskViewModelTests
// 测试 TaskViewModel 的任务操作

@MainActor
final class TaskViewModelTests: XCTestCase {
    var persistence: PersistenceController!
    var mockTaskService: MockTaskService!
    var viewModel: TaskViewModel!

    override func setUp() {
        super.setUp()
        persistence = PersistenceController(inMemory: true)
        mockTaskService = MockTaskService()
        viewModel = TaskViewModel(
            taskService: mockTaskService,
            persistenceController: persistence
        )
    }

    override func tearDown() {
        viewModel = nil
        mockTaskService = nil
        persistence = nil
        super.tearDown()
    }

    // MARK: - 初始状态

    func testInitialState_WhenCreated_ThenTasksAreEmpty() {
        XCTAssertTrue(viewModel.tasks.isEmpty)
        XCTAssertTrue(viewModel.activeTasks.isEmpty)
        XCTAssertTrue(viewModel.completedTasks.isEmpty)
        XCTAssertFalse(viewModel.showCreateSheet)
        XCTAssertNil(viewModel.editingTask)
    }

    // MARK: - 创建任务

    func testCreateTask_GivenValidInput_ThenTaskAddedToList() {
        let context = persistence.viewContext
        let newTask = Task(context: context)
        newTask.id = UUID()
        newTask.title = "新任务"
        newTask.status = TaskStatus.active.rawValue
        newTask.createdAt = Date()
        newTask.updatedAt = Date()

        mockTaskService.createTaskHandler = { _, _, _, _, _ in
            return newTask
        }
        mockTaskService.tasks = [newTask]

        viewModel.createTask(title: "新任务", notes: nil, estimatedPomodoros: 3, priority: 2, dueDate: nil)

        XCTAssertEqual(viewModel.tasks.count, 1)
        XCTAssertEqual(viewModel.tasks.first?.title, "新任务")
        XCTAssertFalse(viewModel.showCreateSheet)
    }

    func testCreateTask_WithEmptyTitle_ThenNotCreated() {
        viewModel.createTask(title: "   ", notes: nil, estimatedPomodoros: 1, priority: 1, dueDate: nil)
        // 由于 title 为空，被 guard 拦截
        XCTAssertTrue(viewModel.tasks.isEmpty)
    }

    // MARK: - 删除任务

    func testDeleteTask_ThenTaskRemovedFromList() {
        let context = persistence.viewContext
        let task = Task(context: context)
        task.id = UUID()
        task.title = "待删除"
        task.status = TaskStatus.active.rawValue
        task.createdAt = Date()
        task.updatedAt = Date()

        var deleted = false
        mockTaskService.deleteTaskHandler = { _ in deleted = true }
        mockTaskService.tasks = [task]

        viewModel.loadTasks()
        XCTAssertEqual(viewModel.tasks.count, 1)

        mockTaskService.tasks = []
        viewModel.deleteTask(task)

        XCTAssertTrue(deleted)
        XCTAssertTrue(viewModel.tasks.isEmpty)
    }

    // MARK: - 完成任务

    func testCompleteTask_ThenStatusBecomesCompleted() {
        let context = persistence.viewContext
        let task = Task(context: context)
        task.id = UUID()
        task.title = "完成任务"
        task.status = TaskStatus.active.rawValue
        task.createdAt = Date()
        task.updatedAt = Date()

        // Mock updateTask to actually modify the task
        mockTaskService.updateTaskHandler = { t, title, notes, estimated, priority, status, dueDate in
            if let s = status { t.status = s }
        }
        mockTaskService.tasks = [task]

        viewModel.loadTasks()
        viewModel.completeTask(task)

        XCTAssertEqual(task.status, TaskStatus.completed.rawValue)
    }

    // MARK: - 重新激活

    func testReactivateTask_ThenStatusBecomesActive() {
        let context = persistence.viewContext
        let task = Task(context: context)
        task.id = UUID()
        task.title = "重新激活"
        task.status = TaskStatus.completed.rawValue
        task.createdAt = Date()
        task.updatedAt = Date()

        mockTaskService.updateTaskHandler = { t, title, notes, estimated, priority, status, dueDate in
            if let s = status { t.status = s }
        }
        mockTaskService.tasks = [task]

        viewModel.loadTasks()
        viewModel.reactivateTask(task)

        XCTAssertEqual(task.status, TaskStatus.active.rawValue)
    }

    // MARK: - 加载

    func testLoadTasks_WhenServiceHasTasks_ThenListsPopulated() {
        let context = persistence.viewContext
        let activeTask = Task(context: context)
        activeTask.id = UUID()
        activeTask.title = "活跃任务"
        activeTask.status = TaskStatus.active.rawValue
        activeTask.createdAt = Date()
        activeTask.updatedAt = Date()

        let completedTask = Task(context: context)
        completedTask.id = UUID()
        completedTask.title = "已完成"
        completedTask.status = TaskStatus.completed.rawValue
        completedTask.createdAt = Date()
        completedTask.updatedAt = Date()

        mockTaskService.tasks = [activeTask, completedTask]

        viewModel.loadTasks()

        XCTAssertEqual(viewModel.tasks.count, 2)
        XCTAssertEqual(viewModel.activeTasks.count, 1)
        XCTAssertEqual(viewModel.completedTasks.count, 1)
    }

    // MARK: - refreshTask

    func testRefreshTask_ThenDoesNotCrash() {
        let context = persistence.viewContext
        let task = Task(context: context)
        task.id = UUID()
        task.title = "原始标题"
        task.status = TaskStatus.active.rawValue
        task.createdAt = Date()
        task.updatedAt = Date()

        mockTaskService.tasks = [task]

        viewModel.loadTasks()
        viewModel.refreshTask(task)

        // refreshTask should not crash
        XCTAssertTrue(true, "refreshTask 不应崩溃")
    }

    // MARK: - 边界条件

    func testLoadTasks_WhenNoTasks_ThenAllEmpty() {
        mockTaskService.tasks = []
        viewModel.loadTasks()

        XCTAssertTrue(viewModel.tasks.isEmpty)
        XCTAssertTrue(viewModel.activeTasks.isEmpty)
        XCTAssertTrue(viewModel.completedTasks.isEmpty)
    }

    func testDeleteTask_WhenNoTasks_DoesNotCrash() {
        mockTaskService.tasks = []
        let context = persistence.viewContext
        let task = Task(context: context)
        task.id = UUID()
        task.title = "不存在"

        viewModel.deleteTask(task)
        XCTAssertTrue(true, "删除不存在的任务不应崩溃")
    }
}

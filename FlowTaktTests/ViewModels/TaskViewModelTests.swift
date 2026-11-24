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
        newTask.storageId = UUID()
        newTask.title = "新任务"
        newTask.status = TaskStatus.active.rawValue
        newTask.createdAt = Date()
        newTask.updatedAt = Date()

        mockTaskService.createTaskHandler = { _, _, _, _, _, _ in
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
        task.storageId = UUID()
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
        task.storageId = UUID()
        task.title = "完成任务"
        task.status = TaskStatus.active.rawValue
        task.createdAt = Date()
        task.updatedAt = Date()

        // Mock updateTask to actually modify the task
        mockTaskService.updateTaskHandler = { t, title, notes, estimated, priority, status, dueDate, recurrenceRule in
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
        task.storageId = UUID()
        task.title = "重新激活"
        task.status = TaskStatus.completed.rawValue
        task.createdAt = Date()
        task.updatedAt = Date()

        mockTaskService.updateTaskHandler = { t, title, notes, estimated, priority, status, dueDate, recurrenceRule in
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
        activeTask.storageId = UUID()
        activeTask.title = "活跃任务"
        activeTask.status = TaskStatus.active.rawValue
        activeTask.createdAt = Date()
        activeTask.updatedAt = Date()

        let completedTask = Task(context: context)
        completedTask.storageId = UUID()
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

    func testUpdateTask_ThenDoesNotCrash() {
        let context = persistence.viewContext
        let task = Task(context: context)
        task.storageId = UUID()
        task.title = "原始标题"
        task.status = TaskStatus.active.rawValue
        task.createdAt = Date()
        task.updatedAt = Date()

        mockTaskService.tasks = [task]

        viewModel.loadTasks()
        viewModel.updateTask(task, title: "新标题", notes: nil, estimatedPomodoros: 2, priority: 2, dueDate: nil)

        // updateTask should not crash
        XCTAssertTrue(true, "updateTask 不应崩溃")
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
        task.storageId = UUID()
        task.title = "不存在"

        viewModel.deleteTask(task)
        XCTAssertTrue(true, "删除不存在的任务不应崩溃")
    }

    // MARK: - 归档（P1.3）

    func testArchiveTask_ThenStatusBecomesArchivedAndAppearsInArchivedList() {
        let context = persistence.viewContext
        let task = Task(context: context)
        task.storageId = UUID()
        task.title = "待归档任务"
        task.status = TaskStatus.active.rawValue
        task.createdAt = Date()
        task.updatedAt = Date()

        mockTaskService.updateTaskHandler = { t, _, _, _, _, status, _, _ in
            if let s = status { t.status = s }
        }
        mockTaskService.tasks = [task]

        viewModel.loadTasks()
        XCTAssertEqual(viewModel.activeTasks.count, 1)
        XCTAssertTrue(viewModel.archivedTasks.isEmpty)

        viewModel.archiveTask(task)

        XCTAssertEqual(task.status, TaskStatus.archived.rawValue)
        // 归档后重新加载，archivedTasks 应刷新
        viewModel.loadTasks()
        XCTAssertEqual(viewModel.archivedTasks.count, 1)
        XCTAssertEqual(viewModel.archivedTasks.first?.title, "待归档任务")
    }

    // ========================================================================
    // MARK: - 排序（A3：截止日期 / 优先级 / 创建时间）
    // ========================================================================

    private func makeTask(title: String, priority: Int16, dueDate: Date?, createdAt: Date) -> Task {
        let task = Task(context: persistence.viewContext)
        task.storageId = UUID()
        task.title = title
        task.status = TaskStatus.active.rawValue
        task.priority = priority
        task.dueDate = dueDate
        task.createdAt = createdAt
        task.updatedAt = createdAt
        task.estimatedPomodoros = 1
        task.completedPomodoros = 0
        task.displayOrder = 0
        return task
    }

    func testSortTasks_ByPriority_ThenHighFirst() {
        // Given
        let low = makeTask(title: "低", priority: 1, dueDate: nil, createdAt: Date())
        let high = makeTask(title: "高", priority: 3, dueDate: nil, createdAt: Date())
        let mid = makeTask(title: "中", priority: 2, dueDate: nil, createdAt: Date())

        // When
        let sorted = TaskViewModel.sortTasks([low, mid, high], by: .priority)

        // Then - 高优先在前
        XCTAssertEqual(sorted.map(\.title), ["高", "中", "低"])
    }

    func testSortTasks_ByPriority_SamePriority_ThenDeterministicByCreatedAt() {
        // 审查修复（2026-08-12）：优先级相同时按创建时间降序，避免同级顺序抖动
        // Given - 两个同优先级任务
        let older = makeTask(title: "较早创建", priority: 2, dueDate: nil, createdAt: Date().addingTimeInterval(-7200))
        let newer = makeTask(title: "较晚创建", priority: 2, dueDate: nil, createdAt: Date().addingTimeInterval(-3600))

        // When
        let sorted = TaskViewModel.sortTasks([older, newer], by: .priority)

        // Then - 同优先级按创建时间降序（确定性强）
        XCTAssertEqual(sorted.map(\.title), ["较晚创建", "较早创建"])
    }

    func testSortTasks_ByDueDate_ThenEarliestFirstAndNilLast() {
        // Given
        let late = makeTask(title: "晚", priority: 2, dueDate: Date().addingTimeInterval(86400 * 3), createdAt: Date())
        let early = makeTask(title: "早", priority: 2, dueDate: Date().addingTimeInterval(86400), createdAt: Date())
        let none = makeTask(title: "无日期", priority: 2, dueDate: nil, createdAt: Date())

        // When
        let sorted = TaskViewModel.sortTasks([late, none, early], by: .dueDate)

        // Then - 截止早的在前，无日期排最后
        XCTAssertEqual(sorted.map(\.title), ["早", "晚", "无日期"])
    }

    func testSortTasks_ByCreatedAt_ThenNewestFirst() {
        // Given
        let old = makeTask(title: "旧", priority: 2, dueDate: nil, createdAt: Date().addingTimeInterval(-3600))
        let new = makeTask(title: "新", priority: 2, dueDate: nil, createdAt: Date())

        // When
        let sorted = TaskViewModel.sortTasks([old, new], by: .createdAt)

        // Then - 最新创建在前
        XCTAssertEqual(sorted.map(\.title), ["新", "旧"])
    }

    func testSortTasks_ByDueDate_SameDate_ThenDeterministicByCreatedAt() {
        // 审查 #19：同截止日期时应按创建时间降序保证确定性
        // Given - 两个任务同一截止日期 + 一个无日期
        let sameDue = Date().addingTimeInterval(86400)
        let older = makeTask(title: "较早创建", priority: 2, dueDate: sameDue, createdAt: Date().addingTimeInterval(-7200))
        let newer = makeTask(title: "较晚创建", priority: 2, dueDate: sameDue, createdAt: Date().addingTimeInterval(-3600))
        let none = makeTask(title: "无日期", priority: 2, dueDate: nil, createdAt: Date())

        // When
        let sorted = TaskViewModel.sortTasks([none, older, newer], by: .dueDate)

        // Then - 同截止日期的按创建时间降序；无日期排最后
        XCTAssertEqual(sorted.map(\.title), ["较晚创建", "较早创建", "无日期"])
    }
}

import XCTest
import CoreData
@testable import FlowTakt

// MARK: - TaskServiceTests
// 测试 TaskService CRUD 操作、状态切换、查询排序

@MainActor
final class TaskServiceTests: XCTestCase {
    var persistence: PersistenceController!
    var taskService: TaskService!

    override func setUp() {
        super.setUp()
        persistence = PersistenceController(inMemory: true)
        taskService = TaskService(persistenceController: persistence)
    }

    override func tearDown() {
        taskService = nil
        persistence = nil
        super.tearDown()
    }

    // ========================================================================
    // MARK: - 创建任务
    // ========================================================================

    func testCreateTask_GivenValidInput_ThenAllPropertiesAreSet() {
        // Given
        let title = "撰写技术方案"
        let estimated: Int16 = 5
        let priority: Int16 = 3
        let dueDate = Date().addingTimeInterval(86400)
        let notes = "需要包含架构图"

        // When
        let task = taskService.createTask(
            title: title,
            notes: notes,
            estimatedPomodoros: estimated,
            priority: priority,
            dueDate: dueDate
        )

        // Then
        XCTAssertEqual(task.title, title)
        XCTAssertEqual(task.notes, notes)
        XCTAssertEqual(task.estimatedPomodoros, estimated)
        XCTAssertEqual(task.priority, priority)
        XCTAssertEqual(task.completedPomodoros, 0)
        XCTAssertEqual(task.status, TaskStatus.active.rawValue)
        XCTAssertEqual(task.dueDate, dueDate)
        XCTAssertNotNil(task.id)
        XCTAssertNotNil(task.createdAt)
        XCTAssertNotNil(task.updatedAt)
    }

    func testCreateTask_WithNilNotes_ThenNotesIsNil() {
        let task = taskService.createTask(
            title: "无备注任务",
            notes: nil,
            estimatedPomodoros: 1,
            priority: 1,
            dueDate: nil
        )
        XCTAssertNil(task.notes)
    }

    func testCreateTask_WithNilDueDate_ThenDueDateIsNil() {
        let task = taskService.createTask(
            title: "无截止日期",
            notes: nil,
            estimatedPomodoros: 1,
            priority: 1,
            dueDate: nil
        )
        XCTAssertNil(task.dueDate)
    }

    // MARK: - 更新任务

    func testUpdateTask_GivenExistingTask_ThenPropertiesAreUpdated() {
        // Given
        let task = taskService.createTask(
            title: "原始标题",
            notes: nil,
            estimatedPomodoros: 2,
            priority: 1,
            dueDate: nil
        )

        // When
        taskService.updateTask(
            task,
            title: "更新后的标题",
            notes: "新增备注",
            estimatedPomodoros: 5,
            priority: 3,
            status: nil,
            dueDate: nil
        )

        // Then
        let fetchedTasks = taskService.fetchAllTasks()
        let updatedTask = fetchedTasks.first(where: { $0.id == task.id })
        XCTAssertNotNil(updatedTask)
        XCTAssertEqual(updatedTask?.title, "更新后的标题")
        XCTAssertEqual(updatedTask?.notes, "新增备注")
        XCTAssertEqual(updatedTask?.estimatedPomodoros, 5)
        XCTAssertEqual(updatedTask?.priority, 3)
    }

    func testUpdateTask_GivenNilParameters_ThenOnlySpecifiedFieldsChange() {
        // Given
        let task = taskService.createTask(
            title: "原始标题",
            notes: "原始备注",
            estimatedPomodoros: 3,
            priority: 2,
            dueDate: nil
        )

        // When - 只更新 title
        taskService.updateTask(
            task,
            title: "新标题",
            notes: nil,
            estimatedPomodoros: nil,
            priority: nil,
            status: nil,
            dueDate: nil
        )

        // Then - 只有 title 变了
        let fetchedTasks = taskService.fetchAllTasks()
        let updated = fetchedTasks.first!
        XCTAssertEqual(updated.title, "新标题")
        XCTAssertEqual(updated.notes, "原始备注")
        XCTAssertEqual(updated.estimatedPomodoros, 3)
        XCTAssertEqual(updated.priority, 2)
    }

    // MARK: - 删除任务

    func testDeleteTask_GivenExistingTask_ThenTaskIsRemoved() {
        // Given
        let task = taskService.createTask(
            title: "待删除任务",
            notes: nil,
            estimatedPomodoros: 1,
            priority: 1,
            dueDate: nil
        )
        XCTAssertEqual(taskService.fetchAllTasks().count, 1)

        // When
        taskService.deleteTask(task)

        // Then
        XCTAssertEqual(taskService.fetchAllTasks().count, 0)
    }

    // MARK: - 完成与激活

    func testUpdateTaskStatus_ToCompleted_ThenStatusBecomesCompleted() {
        // Given
        let task = taskService.createTask(
            title: "完成任务测试",
            notes: nil,
            estimatedPomodoros: 3,
            priority: 2,
            dueDate: nil
        )

        // When
        taskService.updateTask(
            task,
            title: nil,
            notes: nil,
            estimatedPomodoros: nil,
            priority: nil,
            status: TaskStatus.completed.rawValue,
            dueDate: nil
        )

        // Then
        let fetchedTasks = taskService.fetchAllTasks()
        let completedTask = fetchedTasks.first!
        XCTAssertEqual(completedTask.status, TaskStatus.completed.rawValue)
        XCTAssertNotNil(completedTask.completedAt)
    }

    func testCompleteTask_ThenItNoLongerAppearsInActiveTasks() {
        // Given
        let task = taskService.createTask(
            title: "完成即隐藏",
            notes: nil,
            estimatedPomodoros: 1,
            priority: 1,
            dueDate: nil
        )

        // When
        taskService.updateTask(
            task,
            title: nil,
            notes: nil,
            estimatedPomodoros: nil,
            priority: nil,
            status: TaskStatus.completed.rawValue,
            dueDate: nil
        )

        // Then
        let activeTasks = taskService.fetchActiveTasks()
        XCTAssertFalse(activeTasks.contains(where: { $0.id == task.id }))
    }

    func testReactivateTask_ThenAppearsInActiveTasksAgain() {
        // Given
        let task = taskService.createTask(
            title: "重新激活测试",
            notes: nil,
            estimatedPomodoros: 1,
            priority: 1,
            dueDate: nil
        )
        taskService.updateTask(task, title: nil, notes: nil, estimatedPomodoros: nil, priority: nil, status: TaskStatus.completed.rawValue, dueDate: nil)
        XCTAssertEqual(taskService.fetchActiveTasks().count, 0)

        // When
        taskService.updateTask(task, title: nil, notes: nil, estimatedPomodoros: nil, priority: nil, status: TaskStatus.active.rawValue, dueDate: nil)

        // Then
        XCTAssertEqual(taskService.fetchActiveTasks().count, 1)
    }

    // MARK: - 查询

    func testFetchAllTasks_GivenMultipleTasks_ThenReturnsAll() {
        // Given
        _ = taskService.createTask(title: "任务A", notes: nil, estimatedPomodoros: 1, priority: 1, dueDate: nil)
        _ = taskService.createTask(title: "任务B", notes: nil, estimatedPomodoros: 2, priority: 2, dueDate: nil)
        _ = taskService.createTask(title: "任务C", notes: nil, estimatedPomodoros: 3, priority: 3, dueDate: nil)

        // When
        let all = taskService.fetchAllTasks()

        // Then
        XCTAssertEqual(all.count, 3)
    }

    func testFetchActiveTasks_GivenMixedStatus_ThenReturnsOnlyActive() {
        // Given
        let task1 = taskService.createTask(title: "活跃任务", notes: nil, estimatedPomodoros: 1, priority: 1, dueDate: nil)
        let task2 = taskService.createTask(title: "即将完成", notes: nil, estimatedPomodoros: 1, priority: 1, dueDate: nil)
        taskService.updateTask(task2, title: nil, notes: nil, estimatedPomodoros: nil, priority: nil, status: TaskStatus.completed.rawValue, dueDate: nil)

        // When
        let active = taskService.fetchActiveTasks()

        // Then
        XCTAssertEqual(active.count, 1)
        XCTAssertEqual(active.first?.title, "活跃任务")
    }

    func testFetchCompletedTasks_GivenMixedStatus_ThenReturnsOnlyCompleted() {
        // Given
        _ = taskService.createTask(title: "活跃", notes: nil, estimatedPomodoros: 1, priority: 1, dueDate: nil)
        let task2 = taskService.createTask(title: "已完成", notes: nil, estimatedPomodoros: 1, priority: 1, dueDate: nil)
        taskService.updateTask(task2, title: nil, notes: nil, estimatedPomodoros: nil, priority: nil, status: TaskStatus.completed.rawValue, dueDate: nil)

        // When
        let completed = taskService.fetchCompletedTasks()

        // Then
        XCTAssertEqual(completed.count, 1)
        XCTAssertEqual(completed.first?.title, "已完成")
    }

    // MARK: - Pomodoro 计数

    func testIncrementCompletedPomodoros_ThenCountIncreasesByOne() {
        // Given
        let task = taskService.createTask(
            title: "番茄计数测试",
            notes: nil,
            estimatedPomodoros: 5,
            priority: 1,
            dueDate: nil
        )
        XCTAssertEqual(task.completedPomodoros, 0)

        // When
        taskService.incrementCompletedPomodoros(for: task)

        // Then
        XCTAssertEqual(task.completedPomodoros, 1)

        // When (再次增加)
        taskService.incrementCompletedPomodoros(for: task)

        // Then
        XCTAssertEqual(task.completedPomodoros, 2)
    }

    // MARK: - 边界条件

    func testCreateTask_WithMaxPriority_ThenPriorityIsSet() {
        let task = taskService.createTask(title: "高优先级", notes: nil, estimatedPomodoros: 1, priority: 5, dueDate: nil)
        XCTAssertEqual(task.priority, 5)
    }

    func testCreateTask_WithZeroEstimatedPomodoros_ThenTaskIsCreated() {
        let task = taskService.createTask(title: "零预估", notes: nil, estimatedPomodoros: 0, priority: 1, dueDate: nil)
        XCTAssertEqual(task.estimatedPomodoros, 0)
        XCTAssertEqual(task.status, TaskStatus.active.rawValue)
    }

    func testFetchActiveTasks_GivenNoActive_ThenReturnsEmpty() {
        // Given
        let task = taskService.createTask(title: "已完成", notes: nil, estimatedPomodoros: 1, priority: 1, dueDate: nil)
        taskService.updateTask(task, title: nil, notes: nil, estimatedPomodoros: nil, priority: nil, status: TaskStatus.completed.rawValue, dueDate: nil)

        // When
        let active = taskService.fetchActiveTasks()

        // Then
        XCTAssertTrue(active.isEmpty)
    }

    func testFetchAllTasks_GivenNoTasks_ThenReturnsEmpty() {
        let all = taskService.fetchAllTasks()
        XCTAssertTrue(all.isEmpty)
    }

    // ========================================================================
    // MARK: - 回归测试：guard let 保护路径
    // ========================================================================

    func testUpdateTask_GivenDeletedTask_ThenDoesNotCrash() {
        // Given
        let task = taskService.createTask(title: "即将删除", notes: nil, estimatedPomodoros: 1, priority: 1, dueDate: nil)
        let context = persistence.viewContext
        context.delete(task)
        try? context.save()

        // When / Then
        taskService.updateTask(task, title: nil, notes: nil, estimatedPomodoros: nil, priority: nil, status: nil, dueDate: nil)
        XCTAssertTrue(true, "对已删除任务调用 updateTask 不应崩溃")
    }

    func testDeleteTask_GivenAlreadyDeletedTask_ThenDoesNotCrash() {
        // Given
        let task = taskService.createTask(title: "已删除", notes: nil, estimatedPomodoros: 1, priority: 1, dueDate: nil)
        taskService.deleteTask(task)

        // When / Then - 二次删除不应崩溃
        taskService.deleteTask(task)
        XCTAssertTrue(true, "二次删除任务不应崩溃")
    }

    func testIncrementPomodoros_GivenDeletedTask_ThenDoesNotCrash() {
        // Given
        let task = taskService.createTask(title: "已删除", notes: nil, estimatedPomodoros: 1, priority: 1, dueDate: nil)
        let context = persistence.viewContext
        context.delete(task)
        try? context.save()

        // When / Then
        taskService.incrementCompletedPomodoros(for: task)
        XCTAssertTrue(true, "对已删除任务调用 incrementCompletedPomodoros 不应崩溃")
    }

    // MARK: - displayOrder 验证

    func testDisplayOrder_GivenNoTasks_ThenFirstTaskStartsAtZero() {
        // Given - 无任务

        // When
        let task = taskService.createTask(title: "首个任务", notes: nil, estimatedPomodoros: 1, priority: 1, dueDate: nil)

        // Then
        XCTAssertEqual(task.displayOrder, 0, "首个任务的 displayOrder 应为 0")
    }

    func testDisplayOrder_GivenMultipleTasks_ThenDisplayOrdersAscending() {
        // Given
        let task1 = taskService.createTask(title: "任务1", notes: nil, estimatedPomodoros: 1, priority: 1, dueDate: nil)
        let task2 = taskService.createTask(title: "任务2", notes: nil, estimatedPomodoros: 1, priority: 1, dueDate: nil)
        let task3 = taskService.createTask(title: "任务3", notes: nil, estimatedPomodoros: 1, priority: 1, dueDate: nil)

        // Then
        XCTAssertEqual(task1.displayOrder, 0)
        XCTAssertEqual(task2.displayOrder, 1)
        XCTAssertEqual(task3.displayOrder, 2)
    }
}

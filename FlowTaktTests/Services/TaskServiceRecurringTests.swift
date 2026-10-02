import XCTest
import CoreData
@testable import FlowTakt

// MARK: - TaskServiceRecurringTests
// 专项测试 TaskService 重复任务生成算法（handleRecurringTaskCompletion / nextDate）

@MainActor
final class TaskServiceRecurringTests: XCTestCase {
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
    // MARK: - 完成重复任务时生成下一实例
    // ========================================================================

    func testCompleteRecurringTask_Daily_ThenCreatesNextInstance() {
        // Given
        let dueDate = Date()
        let task = taskService.createTask(
            title: "每日站会",
            notes: nil,
            estimatedPomodoros: 1,
            priority: 2,
            dueDate: dueDate,
            recurrenceRule: "daily"
        )

        // When
        taskService.updateTask(task, status: TaskStatus.completed.rawValue)

        // Then
        let activeTasks = taskService.fetchActiveTasks()
        XCTAssertEqual(activeTasks.count, 1, "完成 daily 重复任务后应生成 1 个新的 active 实例")
        let nextTask = activeTasks.first!
        XCTAssertEqual(nextTask.title, "每日站会")
        XCTAssertTrue(nextTask.isRecurring)
        XCTAssertEqual(nextTask.recurrenceRule, "daily")
        // 下一实例的 dueDate 应为原 dueDate + 1 天
        let calendar = Calendar.current
        XCTAssertEqual(calendar.startOfDay(for: nextTask.dueDate!),
                      calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: dueDate)!))
        // displayOrder 应为原 + 1，避免冲突
        XCTAssertEqual(nextTask.displayOrder, task.displayOrder + 1)
        // completedPomodoros 应重置为 0
        XCTAssertEqual(nextTask.completedPomodoros, 0)
    }

    func testCompleteRecurringTask_Weekly_ThenCreatesNextInstance() {
        // Given
        let dueDate = Date()
        let task = taskService.createTask(
            title: "周报",
            notes: nil,
            estimatedPomodoros: 2,
            priority: 2,
            dueDate: dueDate,
            recurrenceRule: "weekly"
        )

        // When
        taskService.updateTask(task, status: TaskStatus.completed.rawValue)

        // Then
        let activeTasks = taskService.fetchActiveTasks()
        XCTAssertEqual(activeTasks.count, 1)
        let nextTask = activeTasks.first!
        let calendar = Calendar.current
        XCTAssertEqual(calendar.startOfDay(for: nextTask.dueDate!),
                      calendar.startOfDay(for: calendar.date(byAdding: .weekOfYear, value: 1, to: dueDate)!))
    }

    func testCompleteRecurringTask_Monthly_ThenCreatesNextInstance() {
        // Given
        let dueDate = Date()
        let task = taskService.createTask(
            title: "月度复盘",
            notes: nil,
            estimatedPomodoros: 3,
            priority: 1,
            dueDate: dueDate,
            recurrenceRule: "monthly"
        )

        // When
        taskService.updateTask(task, status: TaskStatus.completed.rawValue)

        // Then
        let activeTasks = taskService.fetchActiveTasks()
        XCTAssertEqual(activeTasks.count, 1)
        let nextTask = activeTasks.first!
        let calendar = Calendar.current
        XCTAssertEqual(calendar.startOfDay(for: nextTask.dueDate!),
                      calendar.startOfDay(for: calendar.date(byAdding: .month, value: 1, to: dueDate)!))
    }

    func testCompleteRecurringTask_Yearly_ThenCreatesNextInstance() {
        // Given
        let dueDate = Date()
        let task = taskService.createTask(
            title: "年度总结",
            notes: nil,
            estimatedPomodoros: 5,
            priority: 3,
            dueDate: dueDate,
            recurrenceRule: "yearly"
        )

        // When
        taskService.updateTask(task, status: TaskStatus.completed.rawValue)

        // Then
        let activeTasks = taskService.fetchActiveTasks()
        XCTAssertEqual(activeTasks.count, 1)
        let nextTask = activeTasks.first!
        let calendar = Calendar.current
        XCTAssertEqual(calendar.startOfDay(for: nextTask.dueDate!),
                      calendar.startOfDay(for: calendar.date(byAdding: .year, value: 1, to: dueDate)!))
    }

    func testCompleteRecurringTask_Biweekly_ThenCreatesNextInstance() {
        // Given
        let dueDate = Date()
        let task = taskService.createTask(
            title: "双周会",
            notes: nil,
            estimatedPomodoros: 2,
            priority: 2,
            dueDate: dueDate,
            recurrenceRule: "biweekly"
        )

        // When
        taskService.updateTask(task, status: TaskStatus.completed.rawValue)

        // Then
        let activeTasks = taskService.fetchActiveTasks()
        XCTAssertEqual(activeTasks.count, 1)
        let nextTask = activeTasks.first!
        let calendar = Calendar.current
        XCTAssertEqual(calendar.startOfDay(for: nextTask.dueDate!),
                      calendar.startOfDay(for: calendar.date(byAdding: .weekOfYear, value: 2, to: dueDate)!))
    }

    // ========================================================================
    // MARK: - weekday 工作日规则（跳过周末）
    // ========================================================================

    func testCompleteRecurringTask_Weekday_Friday_ThenNextIsMonday() {
        // Given：构造一个周五的截止日期
        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = 26 // 2026-06-26 是周五
        let friday = Calendar.current.date(from: components)!
        let task = taskService.createTask(
            title: "工作日任务",
            notes: nil,
            estimatedPomodoros: 1,
            priority: 2,
            dueDate: friday,
            recurrenceRule: "weekday"
        )

        // When
        taskService.updateTask(task, status: TaskStatus.completed.rawValue)

        // Then：下一个工作日应为下周一（2026-06-29）
        let activeTasks = taskService.fetchActiveTasks()
        XCTAssertEqual(activeTasks.count, 1)
        let nextTask = activeTasks.first!
        let calendar = Calendar.current
        let nextDueDate = nextTask.dueDate!
        let weekday = calendar.component(.weekday, from: nextDueDate)
        XCTAssertEqual(weekday, 2, "周五完成 weekday 任务后，下一个应为周一（weekday=2）")
    }

    func testCompleteRecurringTask_Weekday_Sunday_ThenNextIsMonday() {
        // Given：构造一个周日的截止日期
        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = 28 // 2026-06-28 是周日
        let sunday = Calendar.current.date(from: components)!
        let task = taskService.createTask(
            title: "周日任务",
            notes: nil,
            estimatedPomodoros: 1,
            priority: 2,
            dueDate: sunday,
            recurrenceRule: "weekday"
        )

        // When
        taskService.updateTask(task, status: TaskStatus.completed.rawValue)

        // Then：下一个工作日应为周一（2026-06-29）
        let activeTasks = taskService.fetchActiveTasks()
        XCTAssertEqual(activeTasks.count, 1)
        let nextTask = activeTasks.first!
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: nextTask.dueDate!)
        XCTAssertEqual(weekday, 2, "周日完成 weekday 任务后，下一个应为周一（weekday=2）")
    }

    // ========================================================================
    // MARK: - 重复截止日期 (recurrenceEndDate)
    // ========================================================================

    func testCompleteRecurringTask_AfterEndDate_ThenNoNewInstance() {
        // Given：recurrenceEndDate 已过
        let pastEndDate = Date().addingTimeInterval(-86400) // 昨天
        let dueDate = Date().addingTimeInterval(-86400 * 2) // 前天
        let task = taskService.createTask(
            title: "已截止重复任务",
            notes: nil,
            estimatedPomodoros: 1,
            priority: 2,
            dueDate: dueDate,
            recurrenceRule: "daily"
        )
        task.recurrenceEndDate = pastEndDate

        // When
        taskService.updateTask(task, status: TaskStatus.completed.rawValue)

        // Then：超过截止日期，不应生成下一实例
        let activeTasks = taskService.fetchActiveTasks()
        XCTAssertEqual(activeTasks.count, 0, "超过 recurrenceEndDate 后不应再生成下一实例")
    }

    // ========================================================================
    // MARK: - 无 dueDate 时以当前时间为基准
    // ========================================================================

    func testCompleteRecurringTask_NoDueDate_ThenUsesCurrentDate() {
        // Given
        let task = taskService.createTask(
            title: "无截止日期的重复任务",
            notes: nil,
            estimatedPomodoros: 1,
            priority: 2,
            dueDate: nil,
            recurrenceRule: "daily"
        )

        // When
        let beforeComplete = Date()
        taskService.updateTask(task, status: TaskStatus.completed.rawValue)
        let afterComplete = Date()

        // Then：下一实例应有 dueDate，约为 当前时间 + 1 天
        let activeTasks = taskService.fetchActiveTasks()
        XCTAssertEqual(activeTasks.count, 1)
        let nextTask = activeTasks.first!
        XCTAssertNotNil(nextTask.dueDate)
        let calendar = Calendar.current
        let expectedEarliest = calendar.date(byAdding: .day, value: 1, to: beforeComplete)!
        let expectedLatest = calendar.date(byAdding: .day, value: 1, to: afterComplete)!
        XCTAssertGreaterThanOrEqual(nextTask.dueDate!, expectedEarliest.addingTimeInterval(-1))
        XCTAssertLessThanOrEqual(nextTask.dueDate!, expectedLatest.addingTimeInterval(1))
    }

    // ========================================================================
    // MARK: - 完成非重复任务不生成新实例
    // ========================================================================

    func testCompleteNonRecurringTask_ThenNoNewInstance() {
        // Given
        let task = taskService.createTask(
            title: "一次性任务",
            notes: nil,
            estimatedPomodoros: 1,
            priority: 2,
            dueDate: Date(),
            recurrenceRule: nil
        )

        // When
        taskService.updateTask(task, status: TaskStatus.completed.rawValue)

        // Then
        let activeTasks = taskService.fetchActiveTasks()
        XCTAssertEqual(activeTasks.count, 0, "完成非重复任务不应生成新实例")
    }

    // ========================================================================
    // MARK: - 幂等：重复完成 / 完成→激活→再完成 不产生重复实例
    // ========================================================================

    func testCompleteRecurringTask_Twice_ThenOnlyOneNextInstance() {
        // Given
        let task = taskService.createTask(
            title: "幂等日常任务",
            notes: nil,
            estimatedPomodoros: 1,
            priority: 2,
            dueDate: Date(),
            recurrenceRule: "daily"
        )

        // When - 同一任务重复完成
        taskService.updateTask(task, status: TaskStatus.completed.rawValue)
        taskService.updateTask(task, status: TaskStatus.completed.rawValue)

        // Then - 只应生成 1 个新实例
        let activeTasks = taskService.fetchActiveTasks()
        XCTAssertEqual(activeTasks.count, 1, "重复完成不应产生多个并列的下一实例")
    }

    func testCompleteRecurringTask_ReactivateThenCompleteAgain_ThenNoDuplicateInstance() {
        // Given
        let task = taskService.createTask(
            title: "激活循环任务",
            notes: nil,
            estimatedPomodoros: 1,
            priority: 2,
            dueDate: Date(),
            recurrenceRule: "weekly"
        )
        taskService.updateTask(task, status: TaskStatus.completed.rawValue)
        XCTAssertEqual(taskService.fetchActiveTasks().count, 1)

        // When - 原任务重新激活后再完成（此时已存在同标题 active 实例）
        taskService.updateTask(task, status: TaskStatus.active.rawValue)
        taskService.updateTask(task, status: TaskStatus.completed.rawValue)

        // Then - 仍只应存在 1 个 active 实例
        let activeTasks = taskService.fetchActiveTasks()
        XCTAssertEqual(activeTasks.count, 1, "完成→激活→再完成不应创建重复实例")
    }
}

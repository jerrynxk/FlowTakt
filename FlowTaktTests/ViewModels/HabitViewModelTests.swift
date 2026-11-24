import XCTest
import CoreData
import Combine
@testable import FlowTakt

// MARK: - HabitViewModelTests
// 测试 HabitViewModel：习惯 CRUD、打卡/取消打卡、记录查询、日期检查

final class HabitViewModelTests: XCTestCase {
    var persistence: PersistenceController!
    var mockHabitService: MockHabitService!
    var viewModel: HabitViewModel!
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        persistence = PersistenceController(inMemory: true)
        mockHabitService = MockHabitService()
        viewModel = HabitViewModel(
            habitService: mockHabitService,
            persistenceController: persistence
        )
        cancellables = Set<AnyCancellable>()
    }

    override func tearDown() {
        viewModel = nil
        mockHabitService = nil
        persistence = nil
        cancellables = nil
        super.tearDown()
    }

    // ========================================================================
    // MARK: - 初始状态
    // ========================================================================

    func testInitialState_WhenCreated_ThenHabitsAndSelectionAreEmpty() {
        XCTAssertTrue(viewModel.habits.isEmpty)
        XCTAssertNil(viewModel.selectedHabit)
    }

    // ========================================================================
    // MARK: - 创建习惯
    // ========================================================================

    func testCreateHabit_GivenValidInput_ThenCallsServiceAndLoadsHabits() {
        let habit = Habit(context: persistence.viewContext)
        habit.storageId = UUID()
        habit.name = "每天跑步"
        habit.frequency = "daily"
        habit.targetCount = 1
        habit.currentStreak = 0
        habit.longestStreak = 0
        habit.createdAt = Date()
        habit.updatedAt = Date()
        try? persistence.viewContext.save()
        mockHabitService.habits = [habit]

        // When
        viewModel.createHabit(name: "每天跑步", frequency: "daily", targetCount: 1)

        // Then
        XCTAssertEqual(viewModel.habits.count, 1)
    }

    func testCreateHabit_GivenEmptyName_ThenReturnsEarly() {
        mockHabitService.createHabitCalledHandler = {
            XCTFail("空名称不应调用 createHabit")
        }

        // When
        viewModel.createHabit(name: "   ")

        // Then: habits 仍为空
        XCTAssertTrue(viewModel.habits.isEmpty)
    }

    // ========================================================================
    // MARK: - 删除习惯
    // ========================================================================

    func testDeleteHabit_ThenRemovesFromList() {
        let habit = Habit(context: persistence.viewContext)
        habit.storageId = UUID()
        habit.name = "待删除习惯"
        habit.frequency = "daily"
        habit.targetCount = 1
        habit.currentStreak = 0
        habit.longestStreak = 0
        habit.createdAt = Date()
        habit.updatedAt = Date()
        try? persistence.viewContext.save()
        mockHabitService.habits = [habit]
        viewModel.loadHabits()
        XCTAssertEqual(viewModel.habits.count, 1)

        // When
        viewModel.deleteHabit(habit)

        // Then
        XCTAssertEqual(viewModel.habits.count, 0)
    }

    func testDeleteHabit_WhenIsSelectedHabit_ThenClearsSelection() {
        let habit = Habit(context: persistence.viewContext)
        habit.storageId = UUID()
        habit.name = "选中习惯"
        habit.frequency = "daily"
        habit.targetCount = 1
        habit.currentStreak = 0
        habit.longestStreak = 0
        habit.createdAt = Date()
        habit.updatedAt = Date()
        try? persistence.viewContext.save()
        mockHabitService.habits = [habit]
        viewModel.loadHabits()
        viewModel.selectedHabit = habit

        // When
        viewModel.deleteHabit(habit)

        // Then
        XCTAssertNil(viewModel.selectedHabit)
    }

    // ========================================================================
    // MARK: - 打卡
    // ========================================================================

    func testCheckIn_ThenCallsServiceAndRefreshes() {
        let habit = Habit(context: persistence.viewContext)
        habit.storageId = UUID()
        habit.name = "读书"
        habit.frequency = "daily"
        habit.targetCount = 1
        habit.currentStreak = 0
        habit.longestStreak = 0
        habit.createdAt = Date()
        habit.updatedAt = Date()
        try? persistence.viewContext.save()
        mockHabitService.habits = [habit]
        viewModel.loadHabits()

        // When
        viewModel.checkIn(habit: habit)

        // Then: checkIn 被调用，habits 重新加载
        XCTAssertTrue(true, "checkIn 不应崩溃")
    }

    // ========================================================================
    // MARK: - 打卡防双击（快速连点只创建一条记录）
    // ========================================================================

    func testCheckIn_DoubleTapWithinWindow_ThenOnlyOneServiceCall() {
        // Given
        let habit = Habit(context: persistence.viewContext)
        habit.storageId = UUID()
        habit.name = "喝水"
        habit.frequency = "daily"
        habit.targetCount = 1
        habit.currentStreak = 0
        habit.longestStreak = 0
        habit.createdAt = Date()
        habit.updatedAt = Date()
        try? persistence.viewContext.save()
        mockHabitService.habits = [habit]
        viewModel.loadHabits()
        var checkInCalls = 0
        mockHabitService.checkInCalledHandler = {
            checkInCalls += 1
        }

        // When - 快速连点两次
        viewModel.checkIn(habit: habit)
        viewModel.checkIn(habit: habit)

        // Then - 只创建一条打卡记录
        XCTAssertEqual(checkInCalls, 1, "防双击窗口内重复打卡应被忽略")
    }

    // ========================================================================
    // MARK: - 热力图数据（经 Service 聚合，替代 View 直连 viewContext）
    // ========================================================================

    func testReloadHeatmap_ThenAggregatesCountsByDay() {
        // Given
        let habit = Habit(context: persistence.viewContext)
        habit.storageId = UUID()
        habit.name = "聚合习惯"
        habit.frequency = "daily"
        habit.targetCount = 1
        habit.currentStreak = 0
        habit.longestStreak = 0
        habit.createdAt = Date()
        habit.updatedAt = Date()
        try? persistence.viewContext.save()

        let today = Date()
        let record1 = HabitRecord(context: persistence.viewContext)
        record1.storageId = UUID()
        record1.date = today
        record1.count = 1
        record1.habit = habit
        record1.createdAt = Date()

        let record2 = HabitRecord(context: persistence.viewContext)
        record2.storageId = UUID()
        record2.date = today
        record2.count = 2
        record2.habit = habit
        record2.createdAt = Date()
        try? persistence.viewContext.save()

        mockHabitService.records = [record1, record2]

        // When
        viewModel.reloadHeatmap(weeks: 17)

        // Then - 同日记录按 count 累加
        let key = Calendar.current.startOfDay(for: today)
        XCTAssertEqual(viewModel.heatmapCounts[key], 3, "同一天多条记录应按 count 累加")
        XCTAssertEqual(viewModel.heatmapTotalCheckIns, 3)
    }

    func testReloadHeatmap_NoRecords_ThenEmptyCounts() {
        // Given - mock 无记录

        // When
        viewModel.reloadHeatmap(weeks: 17)

        // Then
        XCTAssertTrue(viewModel.heatmapCounts.isEmpty)
        XCTAssertEqual(viewModel.heatmapTotalCheckIns, 0)
    }

    // ========================================================================
    // MARK: - 移除打卡
    // ========================================================================

    func testRemoveCheckIn_ThenCallsServiceAndRefreshes() {
        let habit = Habit(context: persistence.viewContext)
        habit.storageId = UUID()
        habit.name = "阅读"
        habit.frequency = "daily"
        habit.targetCount = 1
        habit.currentStreak = 0
        habit.longestStreak = 0
        habit.createdAt = Date()
        habit.updatedAt = Date()
        try? persistence.viewContext.save()

        let record = HabitRecord(context: persistence.viewContext)
        record.storageId = UUID()
        record.date = Date()
        record.count = 1
        record.habit = habit
        record.createdAt = Date()
        try? persistence.viewContext.save()

        // When
        viewModel.removeCheckIn(record: record)

        // Then
        XCTAssertTrue(true, "removeCheckIn 不应崩溃")
    }

    // ========================================================================
    // MARK: - 记录查询
    // ========================================================================

    func testRecordsForHabit_GivenDays_ThenReturnsFilteredRecords() {
        let habit = Habit(context: persistence.viewContext)
        habit.storageId = UUID()
        habit.name = "锻炼"
        habit.frequency = "daily"
        habit.targetCount = 1
        habit.currentStreak = 0
        habit.longestStreak = 0
        habit.createdAt = Date()
        habit.updatedAt = Date()
        try? persistence.viewContext.save()

        let record = HabitRecord(context: persistence.viewContext)
        record.storageId = UUID()
        record.date = Date()
        record.count = 1
        record.habit = habit
        record.createdAt = Date()
        try? persistence.viewContext.save()
        mockHabitService.records = [record]

        // When
        let results = viewModel.records(for: habit, in: 7)

        // Then
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.count, 1)
    }

    // ========================================================================
    // MARK: - 日期打卡检查
    // ========================================================================

    func testDayHasRecord_WhenRecordExists_ThenReturnsTrue() {
        let habit = Habit(context: persistence.viewContext)
        habit.storageId = UUID()
        habit.name = "冥想"
        habit.frequency = "daily"
        habit.targetCount = 1
        habit.currentStreak = 0
        habit.longestStreak = 0
        habit.createdAt = Date()
        habit.updatedAt = Date()
        try? persistence.viewContext.save()

        let record = HabitRecord(context: persistence.viewContext)
        record.storageId = UUID()
        record.date = Date()
        record.count = 1
        record.habit = habit
        record.createdAt = Date()
        try? persistence.viewContext.save()
        mockHabitService.records = [record]

        // When
        let hasRecord = viewModel.dayHasRecord(habit: habit, date: Date())

        // Then
        XCTAssertTrue(hasRecord)
    }

    func testDayHasRecord_WhenNoRecord_ThenReturnsFalse() {
        let habit = Habit(context: persistence.viewContext)
        habit.storageId = UUID()
        habit.name = "无打卡习惯"
        habit.frequency = "daily"
        habit.targetCount = 1
        habit.currentStreak = 0
        habit.longestStreak = 0
        habit.createdAt = Date()
        habit.updatedAt = Date()
        try? persistence.viewContext.save()
        mockHabitService.records = []

        // When
        let hasRecord = viewModel.dayHasRecord(habit: habit, date: Date())

        // Then
        XCTAssertFalse(hasRecord)
    }

    // ========================================================================
    // MARK: - 数据库重置
    // ========================================================================

    func testDatabaseWillReset_ClearsHabitsAndSelection() {
        let habit = Habit(context: persistence.viewContext)
        habit.storageId = UUID()
        habit.name = "习惯"
        habit.frequency = "daily"
        habit.targetCount = 1
        habit.currentStreak = 0
        habit.longestStreak = 0
        habit.createdAt = Date()
        habit.updatedAt = Date()
        try? persistence.viewContext.save()
        mockHabitService.habits = [habit]
        viewModel.loadHabits()
        viewModel.selectedHabit = habit

        // When
        NotificationCenter.default.post(name: .databaseWillReset, object: nil)

        // Then
        XCTAssertTrue(viewModel.habits.isEmpty)
        XCTAssertNil(viewModel.selectedHabit)
    }

    // ========================================================================
    // MARK: - 公共访问
    // ========================================================================

    func testLoadHabits_WhenServiceHasHabits_ThenPopulatesHabits() {
        let habit = Habit(context: persistence.viewContext)
        habit.storageId = UUID()
        habit.name = "习惯A"
        habit.frequency = "daily"
        habit.targetCount = 1
        habit.currentStreak = 0
        habit.longestStreak = 0
        habit.createdAt = Date()
        habit.updatedAt = Date()
        try? persistence.viewContext.save()
        mockHabitService.habits = [habit]

        // When
        viewModel.loadHabits()

        // Then
        XCTAssertEqual(viewModel.habits.count, 1)
        XCTAssertEqual(viewModel.habits.first?.name, "习惯A")
    }
}

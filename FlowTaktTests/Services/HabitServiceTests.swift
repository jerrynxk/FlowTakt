import XCTest
import CoreData
@testable import FlowTakt

// MARK: - HabitServiceTests
// 测试 HabitService 的 createHabit / checkIn / removeCheckIn / fetchAllHabits / fetchHabitRecords / recalculateStreak

@MainActor
final class HabitServiceTests: XCTestCase {
    var persistence: PersistenceController!
    var habitService: HabitService!

    override func setUp() {
        super.setUp()
        persistence = PersistenceController(inMemory: true)
        habitService = HabitService(persistenceController: persistence)
    }

    override func tearDown() {
        habitService = nil
        persistence = nil
        super.tearDown()
    }

    // ========================================================================
    // MARK: - 创建习惯
    // ========================================================================

    func testCreateHabit_GivenValidInput_ThenAllPropertiesAreSet() {
        // Given
        let name = "每天喝水"
        let iconName = "drop"
        let colorHex = "007AFF"
        let frequency = "daily"
        let targetCount: Int16 = 8

        // When
        let habit = habitService.createHabit(
            name: name,
            descriptionText: "保持身体水分",
            iconName: iconName,
            colorHex: colorHex,
            frequency: frequency,
            targetCount: targetCount
        )

        // Then
        XCTAssertEqual(habit.name, name)
        XCTAssertEqual(habit.descriptionText, "保持身体水分")
        XCTAssertEqual(habit.iconName, iconName)
        XCTAssertEqual(habit.colorHex, colorHex)
        XCTAssertEqual(habit.frequency, frequency)
        XCTAssertEqual(habit.targetCount, targetCount)
        XCTAssertEqual(habit.currentStreak, 0)
        XCTAssertEqual(habit.longestStreak, 0)
        XCTAssertNotNil(habit.id)
        XCTAssertNotNil(habit.createdAt)
    }

    // ========================================================================
    // MARK: - 更新习惯
    // ========================================================================

    func testUpdateHabit_GivenPartialFields_ThenOnlyUpdatesProvidedFields() {
        // Given
        let habit = habitService.createHabit(
            name: "原名",
            descriptionText: nil,
            iconName: "star",
            colorHex: nil,
            frequency: "daily",
            targetCount: 1
        )

        // When：只更新 name 和 targetCount
        habitService.updateHabit(habit, name: "新名", targetCount: 5)

        // Then
        XCTAssertEqual(habit.name, "新名")
        XCTAssertEqual(habit.targetCount, 5)
        XCTAssertEqual(habit.iconName, "star") // 未更新
        XCTAssertEqual(habit.frequency, "daily") // 未更新
    }

    // ========================================================================
    // MARK: - 删除习惯
    // ========================================================================

    func testDeleteHabit_ThenRemovedFromFetchAll() {
        // Given
        let habit = habitService.createHabit(
            name: "待删除",
            descriptionText: nil,
            iconName: nil,
            colorHex: nil,
            frequency: "daily",
            targetCount: 1
        )
        XCTAssertEqual(habitService.fetchAllHabits().count, 1)

        // When
        habitService.deleteHabit(habit)

        // Then
        XCTAssertEqual(habitService.fetchAllHabits().count, 0)
    }

    // ========================================================================
    // MARK: - 打卡 (checkIn)
    // ========================================================================

    func testCheckIn_GivenHabit_ThenCreatesRecordAndRecalculatesStreak() {
        // Given
        let habit = habitService.createHabit(
            name: "每天锻炼",
            descriptionText: nil,
            iconName: nil,
            colorHex: nil,
            frequency: "daily",
            targetCount: 1
        )

        // When
        let record = habitService.checkIn(habit: habit, count: 1, note: "完成")

        // Then
        XCTAssertNotNil(record.id)
        XCTAssertEqual(record.count, 1)
        XCTAssertEqual(record.note, "完成")
        XCTAssertEqual(record.habit, habit)
        // 打卡后 streak 应为 1
        XCTAssertEqual(habit.currentStreak, 1)
    }

    // ========================================================================
    // MARK: - 移除打卡 (removeCheckIn)
    // ========================================================================

    func testRemoveCheckIn_ThenRecordDeletedAndStreakRecalculated() {
        // Given
        let habit = habitService.createHabit(
            name: "每天读书",
            descriptionText: nil,
            iconName: nil,
            colorHex: nil,
            frequency: "daily",
            targetCount: 1
        )
        let record = habitService.checkIn(habit: habit, count: 1, note: nil)
        XCTAssertEqual(habit.currentStreak, 1)

        // When
        habitService.removeCheckIn(record)

        // Then
        XCTAssertEqual(habit.currentStreak, 0, "移除打卡后 streak 应为 0")
        let records = habitService.fetchHabitRecords(
            habit: habit,
            from: Date().addingTimeInterval(-86400),
            to: Date().addingTimeInterval(86400)
        )
        XCTAssertEqual(records.count, 0, "记录应被删除")
    }

    // ========================================================================
    // MARK: - fetchAllHabits 排序
    // ========================================================================

    func testFetchAllHabits_WhenMultiple_ThenSortedByCreatedAtDescending() {
        // Given
        _ = habitService.createHabit(name: "习惯A", descriptionText: nil, iconName: nil, colorHex: nil, frequency: "daily", targetCount: 1)
        Thread.sleep(forTimeInterval: 0.01)
        _ = habitService.createHabit(name: "习惯B", descriptionText: nil, iconName: nil, colorHex: nil, frequency: "daily", targetCount: 1)
        Thread.sleep(forTimeInterval: 0.01)
        _ = habitService.createHabit(name: "习惯C", descriptionText: nil, iconName: nil, colorHex: nil, frequency: "daily", targetCount: 1)

        // When
        let habits = habitService.fetchAllHabits()

        // Then：按 createdAt 降序（最新的在前）
        XCTAssertEqual(habits.count, 3)
        XCTAssertEqual(habits[0].name, "习惯C")
        XCTAssertEqual(habits[1].name, "习惯B")
        XCTAssertEqual(habits[2].name, "习惯A")
    }

    // ========================================================================
    // MARK: - fetchHabitRecords 时间范围查询
    // ========================================================================

    func testFetchHabitRecords_GivenDateRange_ThenReturnsRecordsInRange() {
        // Given
        let habit = habitService.createHabit(
            name: "测试习惯",
            descriptionText: nil, iconName: nil, colorHex: nil,
            frequency: "daily", targetCount: 1
        )
        // 创建今天的打卡
        _ = habitService.checkIn(habit: habit, count: 1, note: "今天")

        // When：查询过去 7 天范围
        let calendar = Calendar.current
        let today = Date()
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: today)!
        let records = habitService.fetchHabitRecords(habit: habit, from: weekAgo, to: today)

        // Then
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.note, "今天")
    }

    // ========================================================================
    // MARK: - recalculateStreak daily 连续打卡
    // ========================================================================

    func testRecalculateStreak_Daily_WhenConsecutive3Days_ThenStreakIs3() {
        // Given
        let habit = habitService.createHabit(
            name: "每日打卡",
            descriptionText: nil, iconName: nil, colorHex: nil,
            frequency: "daily", targetCount: 1
        )
        // 模拟 3 天前、2 天前、昨天打卡（不包含今天，因为 recalculateStreak 从当前周期起算）
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        for i in 0..<3 {
            let date = calendar.date(byAdding: .day, value: -i, to: today)!.addingTimeInterval(3600)
            let record = HabitRecord(context: persistence.viewContext)
            record.id = UUID()
            record.date = date
            record.count = 1
            record.note = nil
            record.createdAt = date
            record.habit = habit
        }
        try? persistence.viewContext.save()

        // When
        habitService.recalculateStreak(for: habit)

        // Then
        XCTAssertGreaterThanOrEqual(habit.currentStreak, 3, "连续 3 天打卡，streak 应至少为 3")
    }

    // ========================================================================
    // MARK: - recalculateStreak 无记录时
    // ========================================================================

    func testRecalculateStreak_WhenNoRecords_ThenStreakIs0() {
        // Given
        let habit = habitService.createHabit(
            name: "无打卡习惯",
            descriptionText: nil, iconName: nil, colorHex: nil,
            frequency: "daily", targetCount: 1
        )

        // When
        habitService.recalculateStreak(for: habit)

        // Then
        XCTAssertEqual(habit.currentStreak, 0)
    }

    // ========================================================================
    // MARK: - recalculateStreak 未达到目标次数
    // ========================================================================

    func testRecalculateStreak_Daily_WhenCountLessThanTarget_ThenStreakIs0() {
        // Given：targetCount=3，但今天只打卡 1 次
        let habit = habitService.createHabit(
            name: "高目标习惯",
            descriptionText: nil, iconName: nil, colorHex: nil,
            frequency: "daily", targetCount: 3
        )
        _ = habitService.checkIn(habit: habit, count: 1, note: nil)

        // When
        habitService.recalculateStreak(for: habit)

        // Then：今天打卡数不足目标，streak 应为 0
        XCTAssertEqual(habit.currentStreak, 0, "打卡数不足目标次数时，streak 应为 0")
    }

    // ========================================================================
    // MARK: - longestStreak 更新
    // ========================================================================

    func testRecalculateStreak_WhenNewStreakExceedsLongest_ThenUpdatesLongestStreak() {
        // Given
        let habit = habitService.createHabit(
            name: "突破记录",
            descriptionText: nil, iconName: nil, colorHex: nil,
            frequency: "daily", targetCount: 1
        )
        XCTAssertEqual(habit.longestStreak, 0)

        // When：打卡一次
        _ = habitService.checkIn(habit: habit, count: 1, note: nil)

        // Then：longestStreak 应被更新为 1
        XCTAssertGreaterThanOrEqual(habit.longestStreak, 1)
    }
}

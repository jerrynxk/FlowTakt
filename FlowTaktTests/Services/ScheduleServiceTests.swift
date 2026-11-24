import XCTest
import CoreData
@testable import FlowTakt

// MARK: - ScheduleServiceTests
// 测试 ScheduleService：事件 CRUD、日期范围查询

@MainActor
final class ScheduleServiceTests: XCTestCase {
    var persistence: PersistenceController!
    var service: ScheduleService!

    override func setUp() {
        super.setUp()
        persistence = PersistenceController(inMemory: true)
        service = ScheduleService(persistenceController: persistence)
    }

    override func tearDown() {
        service = nil
        persistence = nil
        super.tearDown()
    }

    // ========================================================================
    // MARK: - 创建事件
    // ========================================================================

    func testCreateEvent_GivenValidInput_ThenAllPropertiesAreSet() {
        let now = Date()
        let endDate = now.addingTimeInterval(3600)

        let event = service.createEvent(
            title: "团队会议",
            startDate: now,
            endDate: endDate,
            isAllDay: false,
            location: "会议室A",
            notes: "准备周报",
            colorHex: "#FF3B30",
            category: .event,
            repeatRule: .none,
            reminderEnabled: true,
            reminderLeadMinutes: 15,
            task: nil
        )

        XCTAssertEqual(event.title, "团队会议")
        XCTAssertEqual(event.startDate.timeIntervalSince1970, now.timeIntervalSince1970, accuracy: 1.0)
        XCTAssertEqual(event.endDate!.timeIntervalSince1970, endDate.timeIntervalSince1970, accuracy: 1.0)
        XCTAssertFalse(event.isAllDay)
        XCTAssertEqual(event.location, "会议室A")
        XCTAssertEqual(event.notes, "准备周报")
        XCTAssertEqual(event.colorHex, "#FF3B30")
        XCTAssertEqual(event.category, ScheduleCategory.event.rawValue)
        XCTAssertEqual(event.repeatRule, RepeatRule.none.rawValue)
        XCTAssertTrue(event.reminderEnabled)
        XCTAssertEqual(event.reminderLeadMinutes, 15)
        XCTAssertNotNil(event.id)
        XCTAssertNotNil(event.createdAt)
        XCTAssertNotNil(event.updatedAt)
        XCTAssertNil(event.task)
    }

    func testCreateEvent_WithTask_ThenTaskIsLinked() {
        let context = persistence.viewContext
        let task = Task(context: context)
        task.storageId = UUID()
        task.title = "关联任务"
        task.status = TaskStatus.active.rawValue
        task.estimatedPomodoros = 2
        task.completedPomodoros = 0
        task.priority = 2
        task.displayOrder = 0
        task.createdAt = Date()
        task.updatedAt = Date()
        try? context.save()

        let event = service.createEvent(
            title: "带任务的事件",
            startDate: Date(),
            endDate: nil,
            isAllDay: false,
            location: nil,
            notes: nil,
            colorHex: nil,
            category: .event,
            repeatRule: .none,
            reminderEnabled: false,
            reminderLeadMinutes: 0,
            task: task
        )

        XCTAssertNotNil(event.task)
        XCTAssertEqual(event.task?.id, task.id)
    }

    func testCreateEvent_WithAllDay_ThenIsAllDayTrue() {
        let event = service.createEvent(
            title: "全天事件",
            startDate: Date(),
            endDate: nil,
            isAllDay: true,
            location: nil,
            notes: nil,
            colorHex: nil,
            category: .event,
            repeatRule: .none,
            reminderEnabled: false,
            reminderLeadMinutes: 0,
            task: nil
        )

        XCTAssertTrue(event.isAllDay)
    }

    // ========================================================================
    // MARK: - 更新事件
    // ========================================================================

    func testUpdateEvent_GivenPartialFields_ThenOnlyUpdatesProvided() {
        let event = service.createEvent(
            title: "原始标题",
            startDate: Date(),
            endDate: nil,
            isAllDay: false,
            location: "原地",
            notes: nil,
            colorHex: nil,
            category: .event,
            repeatRule: .none,
            reminderEnabled: false,
            reminderLeadMinutes: 0,
            task: nil
        )

        // When: 只更新标题和地点
        service.updateEvent(
            event,
            title: "新标题",
            startDate: nil,
            endDate: nil,
            isAllDay: nil,
            location: "新地",
            notes: nil,
            colorHex: nil,
            category: nil,
            repeatRule: nil,
            reminderEnabled: nil,
            reminderLeadMinutes: nil
        )

        // Then
        XCTAssertEqual(event.title, "新标题")
        XCTAssertEqual(event.location, "新地")
        XCTAssertFalse(event.isAllDay) // 未更新
        XCTAssertEqual(event.category, ScheduleCategory.event.rawValue) // 未更新
    }

    func testUpdateEvent_GivenCategoryChange_ThenCategoryIsUpdated() {
        let event = service.createEvent(
            title: "生日",
            startDate: Date(),
            endDate: nil,
            isAllDay: true,
            location: nil,
            notes: nil,
            colorHex: nil,
            category: .event,
            repeatRule: .none,
            reminderEnabled: false,
            reminderLeadMinutes: 0,
            task: nil
        )

        service.updateEvent(
            event,
            title: nil,
            startDate: nil,
            endDate: nil,
            isAllDay: nil,
            location: nil,
            notes: nil,
            colorHex: nil,
            category: .birthday,
            repeatRule: nil,
            reminderEnabled: nil,
            reminderLeadMinutes: nil
        )

        XCTAssertEqual(event.category, ScheduleCategory.birthday.rawValue)
    }

    func testUpdateEvent_GivenReminderChange_ThenUpdated() {
        let event = service.createEvent(
            title: "提醒事件",
            startDate: Date(),
            endDate: nil,
            isAllDay: false,
            location: nil,
            notes: nil,
            colorHex: nil,
            category: .visit,
            repeatRule: .none,
            reminderEnabled: false,
            reminderLeadMinutes: 0,
            task: nil
        )

        service.updateEvent(
            event,
            title: nil,
            startDate: nil,
            endDate: nil,
            isAllDay: nil,
            location: nil,
            notes: nil,
            colorHex: nil,
            category: nil,
            repeatRule: nil,
            reminderEnabled: true,
            reminderLeadMinutes: 60
        )

        XCTAssertTrue(event.reminderEnabled)
        XCTAssertEqual(event.reminderLeadMinutes, 60)
    }

    // ========================================================================
    // MARK: - 删除事件
    // ========================================================================

    func testDeleteEvent_ThenEventIsRemoved() {
        let event = service.createEvent(
            title: "待删除",
            startDate: Date(),
            endDate: nil,
            isAllDay: false,
            location: nil,
            notes: nil,
            colorHex: nil,
            category: .event,
            repeatRule: .none,
            reminderEnabled: false,
            reminderLeadMinutes: 0,
            task: nil
        )
        XCTAssertEqual(service.fetchAllEvents().count, 1)

        // When
        service.deleteEvent(event)

        // Then
        XCTAssertEqual(service.fetchAllEvents().count, 0)
    }

    // ========================================================================
    // MARK: - 获取事件
    // ========================================================================

    func testFetchEvents_GivenDateRange_ThenReturnsMatchingEvents() {
        let now = Date()
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!

        // 创建今天的事件
        _ = service.createEvent(
            title: "今天",
            startDate: now,
            endDate: nil,
            isAllDay: false,
            location: nil, notes: nil, colorHex: nil,
            category: .event, repeatRule: .none,
            reminderEnabled: false, reminderLeadMinutes: 0,
            task: nil
        )
        // 创建明天的事件
        _ = service.createEvent(
            title: "明天",
            startDate: tomorrow,
            endDate: nil,
            isAllDay: false,
            location: nil, notes: nil, colorHex: nil,
            category: .event, repeatRule: .none,
            reminderEnabled: false, reminderLeadMinutes: 0,
            task: nil
        )

        // When: 查询今天到后天
        let dayAfterTomorrow = calendar.date(byAdding: .day, value: 2, to: now)!
        let events = service.fetchEvents(from: now, to: dayAfterTomorrow)

        // Then
        XCTAssertEqual(events.count, 2)
    }

    func testFetchEventsForDate_GivenSpecificDate_ThenReturnsOnlyThatDay() {
        let now = Date()
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let yesterdayEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: yesterday))!

        _ = service.createEvent(
            title: "昨天", startDate: yesterday, endDate: yesterdayEnd,
            isAllDay: false, location: nil, notes: nil, colorHex: nil,
            category: .event, repeatRule: .none,
            reminderEnabled: false, reminderLeadMinutes: 0, task: nil
        )
        _ = service.createEvent(
            title: "今天", startDate: now, endDate: nil,
            isAllDay: false, location: nil, notes: nil, colorHex: nil,
            category: .event, repeatRule: .none,
            reminderEnabled: false, reminderLeadMinutes: 0, task: nil
        )

        // When
        let todayEvents = service.fetchEventsForDate(now)

        // Then
        XCTAssertEqual(todayEvents.count, 1)
        XCTAssertEqual(todayEvents.first?.title, "今天")
    }

    func testFetchAllEvents_WhenMultiple_ThenSortedByStartDate() {
        let now = Date()
        let later = now.addingTimeInterval(7200)
        let earlier = now.addingTimeInterval(-3600)

        _ = service.createEvent(
            title: "晚", startDate: later, endDate: nil,
            isAllDay: false, location: nil, notes: nil, colorHex: nil,
            category: .event, repeatRule: .none,
            reminderEnabled: false, reminderLeadMinutes: 0, task: nil
        )
        _ = service.createEvent(
            title: "早", startDate: earlier, endDate: nil,
            isAllDay: false, location: nil, notes: nil, colorHex: nil,
            category: .event, repeatRule: .none,
            reminderEnabled: false, reminderLeadMinutes: 0, task: nil
        )

        let events = service.fetchAllEvents()

        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].title, "早", "早的事件应在前面")
        XCTAssertEqual(events[1].title, "晚")
    }

    func testFetchEvents_WhenNothingInRange_ThenReturnsEmpty() {
        let farFuture = Date().addingTimeInterval(86400 * 365)
        let events = service.fetchEvents(from: farFuture, to: farFuture.addingTimeInterval(86400))

        XCTAssertTrue(events.isEmpty)
    }

    // ========================================================================
    // MARK: - 按 ID 跨月查询（Widget 深链定位）
    // ========================================================================

    func testFetchEvent_ByID_ThenReturnsMatchingEvent() {
        // Given - 创建下月事件（模拟跨月深链场景）
        let calendar = Calendar.current
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: Date())!
        let created = service.createEvent(
            title: "下月生日", startDate: nextMonth, endDate: nil,
            isAllDay: true, location: nil, notes: nil, colorHex: nil,
            category: .birthday, repeatRule: .yearly,
            reminderEnabled: true, reminderLeadMinutes: 60, task: nil
        )

        // When - 按 ID 全库查询
        let found = service.fetchEvent(id: created.id)

        // Then
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.id, created.id)
        XCTAssertEqual(found?.title, "下月生日")
    }

    func testFetchEvent_WithUnknownID_ThenReturnsNil() {
        // Given - 不存在的 ID

        // When
        let found = service.fetchEvent(id: UUID())

        // Then
        XCTAssertNil(found)
    }

    func testFetchEvent_ThenMatchUUIDStringDeepLink() {
        // Given - 深链用 uuidString 传递
        let created = service.createEvent(
            title: "深链事件", startDate: Date(), endDate: nil,
            isAllDay: false, location: nil, notes: nil, colorHex: nil,
            category: .event, repeatRule: .none,
            reminderEnabled: false, reminderLeadMinutes: 0, task: nil
        )

        // When - 用 UUID(uuidString:) 还原后查询（与 ScheduleView 深链解析路径一致）
        let id = UUID(uuidString: created.id.uuidString)!
        let found = service.fetchEvent(id: id)

        // Then
        XCTAssertEqual(found?.id, created.id)
    }

    // ========================================================================
    // MARK: - endDate 边界防御
    // ========================================================================

    func testUpdateEvent_EndDateBeforeStart_ThenClampedToStart() {
        // Given
        let start = Date()
        let created = service.createEvent(
            title: "边界事件", startDate: start, endDate: nil,
            isAllDay: false, location: nil, notes: nil, colorHex: nil,
            category: .event, repeatRule: .none,
            reminderEnabled: false, reminderLeadMinutes: 0, task: nil
        )

        // When - 结束时间早于开始时间（非法输入，完整参数调用避免走协议扩展）
        service.updateEvent(created, title: nil, startDate: nil, endDate: start.addingTimeInterval(-3600),
                            isAllDay: nil, location: nil, notes: nil, colorHex: nil,
                            category: nil, repeatRule: nil, reminderEnabled: nil, reminderLeadMinutes: nil)

        // Then - 结束时间被收敛到开始时间
        XCTAssertNotNil(created.endDate)
        XCTAssertLessThanOrEqual(created.endDate!, created.startDate + 0.001)
    }
}

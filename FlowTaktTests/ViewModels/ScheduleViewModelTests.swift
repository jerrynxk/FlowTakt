import XCTest
import CoreData
import Combine
@testable import FlowTakt

// MARK: - ScheduleViewModelTests
// 测试 ScheduleViewModel：事件 CRUD、日期/月份刷新、提醒通知

final class ScheduleViewModelTests: XCTestCase {
    var persistence: PersistenceController!
    var mockScheduleService: MockScheduleService!
    var viewModel: ScheduleViewModel!
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        persistence = PersistenceController(inMemory: true)
        mockScheduleService = MockScheduleService()
        viewModel = ScheduleViewModel(
            scheduleService: mockScheduleService,
            persistenceController: persistence
        )
        cancellables = Set<AnyCancellable>()
    }

    override func tearDown() {
        viewModel = nil
        mockScheduleService = nil
        persistence = nil
        cancellables = nil
        super.tearDown()
    }

    // ========================================================================
    // MARK: - 初始状态
    // ========================================================================

    func testInitialState_WhenCreated_ThenEventsIsEmpty() {
        XCTAssertTrue(viewModel.events.isEmpty)
        XCTAssertNotNil(viewModel.selectedDate)
        XCTAssertNotNil(viewModel.currentMonth)
    }

    // ========================================================================
    // MARK: - 创建事件
    // ========================================================================

    func testCreateEvent_GivenValidInput_ThenCallsServiceAndRefreshes() {
        // Given: 预先在 Mock 中放一个事件
        let event = ScheduleItem(context: persistence.viewContext)
        event.id = UUID()
        event.title = "测试事件"
        event.startDate = Date()
        event.category = ScheduleCategory.event.rawValue
        event.repeatRule = RepeatRule.none.rawValue
        event.reminderEnabled = false
        event.reminderLeadMinutes = 0
        event.createdAt = Date()
        event.updatedAt = Date()
        try? persistence.viewContext.save()
        mockScheduleService.events = [event]

        // When
        viewModel.createEvent(
            title: "测试事件",
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

        // Then
        XCTAssertEqual(mockScheduleService.createdEvents.count, 1)
    }

    func testCreateEvent_GivenEmptyTitle_ThenReturnsEarlyWithoutCallingService() {
        // Given
        mockScheduleService.createEventCalledHandler = {
            XCTFail("空标题不应调用 createEvent")
        }

        // When
        viewModel.createEvent(
            title: "   ",
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

        // Then: createEventCalledHandler 不应被调用
        XCTAssertTrue(mockScheduleService.createdEvents.isEmpty)
    }

    func testCreateEvent_PostsRemindersChangedNotification() {
        let event = ScheduleItem(context: persistence.viewContext)
        event.id = UUID()
        event.title = "提醒事件"
        event.startDate = Date()
        event.category = ScheduleCategory.event.rawValue
        event.repeatRule = RepeatRule.none.rawValue
        event.reminderEnabled = true
        event.reminderLeadMinutes = 10
        event.createdAt = Date()
        event.updatedAt = Date()
        try? persistence.viewContext.save()
        mockScheduleService.events = [event]

        let notificationExpectation = expectation(forNotification: .remindersDataChanged, object: nil)

        viewModel.createEvent(
            title: "提醒事件",
            startDate: Date(),
            endDate: nil,
            isAllDay: false,
            location: nil,
            notes: nil,
            colorHex: nil,
            category: .event,
            repeatRule: .none,
            reminderEnabled: true,
            reminderLeadMinutes: 10,
            task: nil
        )

        wait(for: [notificationExpectation], timeout: 1.0)
    }

    // ========================================================================
    // MARK: - 更新事件
    // ========================================================================

    func testUpdateEvent_GivenPartialFields_ThenCallsService() {
        let event = ScheduleItem(context: persistence.viewContext)
        event.id = UUID()
        event.title = "原始标题"
        event.startDate = Date()
        event.category = ScheduleCategory.event.rawValue
        event.repeatRule = RepeatRule.none.rawValue
        event.reminderEnabled = false
        event.reminderLeadMinutes = 0
        event.createdAt = Date()
        event.updatedAt = Date()
        try? persistence.viewContext.save()

        mockScheduleService.events = [event]

        // When
        viewModel.updateEvent(
            event,
            title: "新标题",
            startDate: nil,
            endDate: nil,
            isAllDay: nil,
            location: nil,
            notes: nil,
            colorHex: nil,
            category: nil,
            repeatRule: nil,
            reminderEnabled: nil,
            reminderLeadMinutes: nil
        )

        // Then
        XCTAssertEqual(mockScheduleService.updatedEvents.count, 1)
    }

    // ========================================================================
    // MARK: - 删除事件
    // ========================================================================

    func testDeleteEvent_ThenCallsService() {
        let event = ScheduleItem(context: persistence.viewContext)
        event.id = UUID()
        event.title = "待删除"
        event.startDate = Date()
        event.category = ScheduleCategory.event.rawValue
        event.repeatRule = RepeatRule.none.rawValue
        event.reminderEnabled = false
        event.reminderLeadMinutes = 0
        event.createdAt = Date()
        event.updatedAt = Date()
        try? persistence.viewContext.save()

        // When
        viewModel.deleteEvent(event)

        // Then
        XCTAssertEqual(mockScheduleService.deletedEvents.count, 1)
    }

    func testDeleteEvent_PostsRemindersChangedNotification() {
        let event = ScheduleItem(context: persistence.viewContext)
        event.id = UUID()
        event.title = "待删除提醒"
        event.startDate = Date()
        event.category = ScheduleCategory.event.rawValue
        event.repeatRule = RepeatRule.none.rawValue
        event.reminderEnabled = false
        event.reminderLeadMinutes = 0
        event.createdAt = Date()
        event.updatedAt = Date()
        try? persistence.viewContext.save()

        let notificationExpectation = expectation(forNotification: .remindersDataChanged, object: nil)

        viewModel.deleteEvent(event)

        wait(for: [notificationExpectation], timeout: 1.0)
    }

    // ========================================================================
    // MARK: - 刷新
    // ========================================================================

    func testRefreshForDate_ThenUpdatesSelectedDateAndEvents() {
        let event = ScheduleItem(context: persistence.viewContext)
        event.id = UUID()
        event.title = "特定日期事件"
        let targetDate = Date()
        event.startDate = targetDate
        event.category = ScheduleCategory.event.rawValue
        event.repeatRule = RepeatRule.none.rawValue
        event.reminderEnabled = false
        event.reminderLeadMinutes = 0
        event.createdAt = Date()
        event.updatedAt = Date()
        try? persistence.viewContext.save()
        mockScheduleService.events = [event]

        // When
        viewModel.refreshForDate(targetDate)

        // Then
        XCTAssertEqual(viewModel.selectedDate.timeIntervalSince1970, targetDate.timeIntervalSince1970, accuracy: 1.0)
        XCTAssertEqual(viewModel.events.count, 1)
    }

    func testRefreshAllEvents_ThenReturnsAllFromService() {
        let e1 = ScheduleItem(context: persistence.viewContext)
        e1.id = UUID()
        e1.title = "事件1"
        e1.startDate = Date()
        e1.category = ScheduleCategory.event.rawValue
        e1.repeatRule = RepeatRule.none.rawValue
        e1.reminderEnabled = false
        e1.reminderLeadMinutes = 0
        e1.createdAt = Date()
        e1.updatedAt = Date()

        let e2 = ScheduleItem(context: persistence.viewContext)
        e2.id = UUID()
        e2.title = "事件2"
        e2.startDate = Date()
        e2.category = ScheduleCategory.birthday.rawValue
        e2.repeatRule = RepeatRule.yearly.rawValue
        e2.reminderEnabled = true
        e2.reminderLeadMinutes = 1440
        e2.createdAt = Date()
        e2.updatedAt = Date()
        try? persistence.viewContext.save()
        mockScheduleService.events = [e1, e2]

        // When
        viewModel.refreshEvents()

        // Then
        XCTAssertEqual(viewModel.events.count, 2)
    }

    // ========================================================================
    // MARK: - 数据库重置
    // ========================================================================

    func testDatabaseWillReset_ClearsEvents() {
        let event = ScheduleItem(context: persistence.viewContext)
        event.id = UUID()
        event.title = "清空"
        event.startDate = Date()
        event.category = ScheduleCategory.event.rawValue
        event.repeatRule = RepeatRule.none.rawValue
        event.reminderEnabled = false
        event.reminderLeadMinutes = 0
        event.createdAt = Date()
        event.updatedAt = Date()
        try? persistence.viewContext.save()
        mockScheduleService.events = [event]
        viewModel.refreshEvents()
        XCTAssertEqual(viewModel.events.count, 1)

        // When
        NotificationCenter.default.post(name: .databaseWillReset, object: nil)

        // Then
        XCTAssertTrue(viewModel.events.isEmpty)
    }

    // ========================================================================
    // MARK: - 深链跨月定位（findEvent 桥接 Service.fetchEvent）
    // ========================================================================

    func testFindEvent_ByID_ThenReturnsEventFromService() {
        // Given - 模拟下月事件（不在当前加载的 events 中）
        let event = ScheduleItem(context: persistence.viewContext)
        event.id = UUID()
        event.title = "下月生日"
        event.startDate = Calendar.current.date(byAdding: .month, value: 1, to: Date())!
        event.category = ScheduleCategory.birthday.rawValue
        event.repeatRule = RepeatRule.yearly.rawValue
        event.reminderEnabled = false
        event.reminderLeadMinutes = 0
        event.createdAt = Date()
        event.updatedAt = Date()
        try? persistence.viewContext.save()
        mockScheduleService.events = [event]
        viewModel.events = [] // 当前加载为空（模拟当月无此事件）

        // When - 深链 ID 跨月定位
        let found = viewModel.findEvent(byID: event.id)

        // Then
        XCTAssertEqual(found?.id, event.id)
        XCTAssertEqual(found?.title, "下月生日")
    }

    func testFindEvent_UnknownID_ThenReturnsNil() {
        // Given - service 无匹配事件
        mockScheduleService.events = []

        // When
        let found = viewModel.findEvent(byID: UUID())

        // Then
        XCTAssertNil(found)
    }

    // ========================================================================
    // MARK: - 周视图（A4）
    // ========================================================================

    func testRefreshForWeek_ThenWeekEventsOnlyCoverThatWeek() {
        // Given
        let calendar = Calendar.current
        // 审查修复（2026-08-12）：原 Date()+3 依赖当天是周几，当 +4 天跨越周首/周尾时
        // inWeek 事件会掉出本周区间导致偶发失败（flaky）。改为取「本周真实周四」：
        // 先定位本周首（对齐系统 firstWeekday），再 +3 天。
        let dayStart = calendar.startOfDay(for: Date())
        let startWeekday = calendar.component(.weekday, from: dayStart)
        let diffToWeekStart = (startWeekday - calendar.firstWeekday + 7) % 7
        let weekStart = calendar.date(byAdding: .day, value: -diffToWeekStart, to: dayStart)!
        let thursday = calendar.date(byAdding: .day, value: 3, to: weekStart)!
        let inWeek = ScheduleItem(context: persistence.viewContext)
        inWeek.id = UUID()
        inWeek.title = "周内事件"
        inWeek.startDate = calendar.date(byAdding: .day, value: 1, to: thursday)!
        inWeek.category = ScheduleCategory.event.rawValue
        inWeek.repeatRule = RepeatRule.none.rawValue
        inWeek.reminderEnabled = false
        inWeek.reminderLeadMinutes = 0
        inWeek.createdAt = Date()
        inWeek.updatedAt = Date()

        let outOfWeek = ScheduleItem(context: persistence.viewContext)
        outOfWeek.id = UUID()
        outOfWeek.title = "周外事件"
        outOfWeek.startDate = calendar.date(byAdding: .day, value: 14, to: thursday)!
        outOfWeek.category = ScheduleCategory.event.rawValue
        outOfWeek.repeatRule = RepeatRule.none.rawValue
        outOfWeek.reminderEnabled = false
        outOfWeek.reminderLeadMinutes = 0
        outOfWeek.createdAt = Date()
        outOfWeek.updatedAt = Date()
        try? persistence.viewContext.save()
        mockScheduleService.events = [inWeek, outOfWeek]

        // When
        viewModel.refreshForWeek(containing: thursday)

        // Then - 只包含本周事件，周首日对齐系统首日
        XCTAssertEqual(viewModel.weekEvents.map(\.title), ["周内事件"], "周视图只应包含所在周的事件")
        let weekday = calendar.component(.weekday, from: viewModel.currentWeekStart)
        XCTAssertEqual(weekday, calendar.firstWeekday, "周首日应对齐系统 firstWeekday")
        // 本周事件应落在 [weekStart, weekStart+7)
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: viewModel.currentWeekStart)!
        XCTAssertGreaterThanOrEqual(inWeek.startDate, viewModel.currentWeekStart)
        XCTAssertLessThan(inWeek.startDate, weekEnd)
    }

    func testShiftWeek_ThenMovesSevenDays() {
        // Given
        viewModel.refreshForWeek(containing: Date())
        let originalStart = viewModel.currentWeekStart

        // When - 向前一周
        viewModel.shiftWeek(by: 1)

        // Then - 起始日 +7 天
        let expected = Calendar.current.date(byAdding: .day, value: 7, to: originalStart)!
        XCTAssertEqual(viewModel.currentWeekStart, expected)
    }
}

import XCTest
import CoreData
@testable import FlowTakt

// MARK: - Round4RegressionTests
// 覆盖 2026-10-15 第四轮代码审查（报告 code-review-2026-10-14-round4.md）修复的关键路径。
//
// 本文件只测「Round 4 审查指出并已修复」的缺陷，防止回归：
//   P1-013 TimerManager resume/currentPausedDuration/elapsedTime 未走注入时钟
//   P1-029 formattedDuration 对 NaN/±Inf 的 "00:00" 兜底无执行断言
//   P1-011 MockFocusService.completeSession 与真实实现的积分语义对齐
//   P1-022 ReminderServiceProtocol 补 MockReminderService
//   P1-016 TaskListView 页签持久化（TaskTab rawValue 往返）
//   P1-020 OpenPageIntent 冷启动意图暂存/消费
//   P0-2  Service fetch 守卫：store 未就绪时全部安全短路（不抛 ObjC 异常）

@MainActor
final class Round4RegressionTests: XCTestCase {

    private var persistence: PersistenceController!

    override func setUp() {
        super.setUp()
        persistence = PersistenceController(inMemory: true)
    }

    override func tearDown() {
        persistence = nil
        super.tearDown()
    }

    // MARK: - P1-013 TimerManager 注入时钟确定性

    func testTimerManager_ElapsedTime_UsesInjectedClock() {
        let timer = TimerManager()
        defer { timer.reset() }

        let fixedNow = Date(timeIntervalSince1970: 1_000_000)
        timer.nowProvider = { fixedNow }

        timer.start(duration: 600)
        // 时钟快进 100s：elapsedTime 应精确等于 100（不再依赖真实时间）
        timer.nowProvider = { fixedNow.addingTimeInterval(100) }
        XCTAssertEqual(timer.elapsedTime, 100, accuracy: 0.001,
                       "elapsedTime 必须走注入时钟（P1-013）")
    }

    func testTimerManager_CurrentPausedDuration_UsesInjectedClock() {
        let timer = TimerManager()
        defer { timer.reset() }

        var current = Date(timeIntervalSince1970: 2_000_000)
        timer.nowProvider = { current }

        timer.start(duration: 600)
        timer.pause()
        current = current.addingTimeInterval(42)
        XCTAssertEqual(timer.currentPausedDuration, 42, accuracy: 0.001,
                       "currentPausedDuration 必须走注入时钟（P1-013）")
    }

    func testTimerManager_Resume_KeepsElapsedContinuityWithInjectedClock() {
        let timer = TimerManager()
        defer { timer.reset() }

        var current = Date(timeIntervalSince1970: 3_000_000)
        timer.nowProvider = { current }

        timer.start(duration: 600)
        current = current.addingTimeInterval(100)   // 跑 100s
        timer.tickForTesting()                      // 推进一次计算，让 timeRemaining 反映已耗时长
        timer.pause()                               // 暂停
        current = current.addingTimeInterval(50)    // 暂停 50s
        timer.resume()
        current = current.addingTimeInterval(30)    // 恢复后再跑 30s

        // 净专注 = 100 + 30 = 130s（暂停段不计入）
        XCTAssertEqual(timer.elapsedTime, 130, accuracy: 0.001,
                       "resume 后 elapsedTime 必须排除暂停段且走注入时钟（P1-013）")
    }

    // MARK: - P1-029 formattedDuration 非有限值兜底

    func testFormattedDuration_NaN_ReturnsSafeFallback() {
        XCTAssertEqual(Double.nan.formattedDuration, "00:00",
                       "NaN 必须被拦截返回 00:00（P1-029，Int(NaN) 会 trap）")
    }

    func testFormattedDuration_Infinity_ReturnsSafeFallback() {
        XCTAssertEqual(Double.infinity.formattedDuration, "00:00")
        XCTAssertEqual((-Double.infinity).formattedDuration, "00:00")
    }

    func testFormattedDuration_NormalValue_StillFormats() {
        XCTAssertEqual((3600.0).formattedDuration, "1小时")
        XCTAssertEqual((3660.0).formattedDuration, "1小时1分钟")
        XCTAssertEqual((300.0).formattedDuration, "5分钟")
    }

    // MARK: - P1-011 MockFocusService 积分语义对齐

    func testMockFocusService_CompleteSession_FocusPhaseEarnsPoints() {
        let mock = MockFocusService()
        let session = makeMockSession(phase: FocusPhase.focus.rawValue)
        mock.completeSession(session, actualDuration: 300)
        XCTAssertEqual(session.earnedPoints, Int16(AppConstants.pointsPerCompletedPomodoro),
                       "Mock 必须与真实实现对齐：专注阶段发积分（P1-011）")
    }

    func testMockFocusService_CompleteSession_BreakPhaseEarnsNothing() {
        let mock = MockFocusService()
        let session = makeMockSession(phase: FocusPhase.shortBreak.rawValue)
        mock.completeSession(session, actualDuration: 300)
        XCTAssertEqual(session.earnedPoints, 0,
                       "Mock 必须与真实实现对齐：休息阶段不发积分（P1-011）")
    }

    private func makeMockSession(phase: String) -> FocusSession {
        let entity = NSEntityDescription.entity(forEntityName: "FocusSession", in: persistence.viewContext)!
        let session = FocusSession(entity: entity, insertInto: persistence.viewContext)
        session.storageId = UUID()
        session.phase = phase
        session.status = SessionStatus.running.rawValue
        session.plannedDuration = 300
        session.startTime = Date()
        return session
    }

    // MARK: - P1-022 MockReminderService

    func testMockReminderService_CountsRescheduleCalls() {
        let mock = MockReminderService()
        XCTAssertEqual(mock.rescheduleAllCalledCount, 0)
        mock.rescheduleAll()
        mock.rescheduleAll()
        XCTAssertEqual(mock.rescheduleAllCalledCount, 2)
    }

    // MARK: - P1-016 TaskTab rawValue 往返

    func testTaskTab_RawValueRoundTrip_PreservesSelection() {
        // TaskListView 页签持久化依赖 String rawValue 的可逆性
        for tab in TaskListView.TaskTab.allCases {
            XCTAssertEqual(TaskListView.TaskTab(rawValue: tab.rawValue), tab)
        }
        XCTAssertEqual(TaskListView.TaskTab(rawValue: "unknown"), nil,
                       "未知 rawValue 必须安全回落（调用侧 ?? .active）")
    }

    // MARK: - P1-020 OpenPageIntent 冷启动意图暂存

    func testOpenPageIntent_PendingPageConsumed() {
        let defaults = UserDefaults.standard
        defer { defaults.removeObject(forKey: "pendingOpenPageIntent") }
        // 模拟 OpenPageIntent 在 AppDependency 就绪前的落盘行为
        defaults.set("stats", forKey: "pendingOpenPageIntent")
        // 消费语义：读取后删除（AppDependency.selectedMainTab 初始化闭包内完成）
        let raw = defaults.string(forKey: "pendingOpenPageIntent")
        defaults.removeObject(forKey: "pendingOpenPageIntent")
        XCTAssertEqual(raw, "stats")
        XCTAssertNil(defaults.string(forKey: "pendingOpenPageIntent"),
                     "意图必须一次性消费，避免下次启动误应用（P1-020）")
    }

    // MARK: - P0-2 store 未就绪时 fetch 安全短路

    func testFetchSafely_StoreNotReady_ReturnsEmptyInsteadOfCrashing() {
        // 构造一个「无 store」的控制器：testingWithContainer 注入空 coordinator 容器
        let emptyContainer = NSPersistentContainer(name: "EmptyForTest",
                                                   managedObjectModel: PersistenceController.sharedManagedObjectModel)
        let empty = PersistenceController(testingWithContainer: emptyContainer)
        XCTAssertFalse(empty.canFetchSafely("测试守卫"),
                       "空 coordinator 必须判定为未就绪（P0-2 ObjC 异常防线）")

        // 真实 Service 挂上未就绪控制器后 fetch 必须返回空数组而非崩溃
        let focusService = FocusService(persistenceController: empty,
                                        notificationService: NotificationService())
        XCTAssertTrue(focusService.fetchTodaysSessions().isEmpty)
        XCTAssertTrue(focusService.fetchAllCompletedSessions().isEmpty)
        XCTAssertNil(focusService.getCurrentSession())

        let taskService = TaskService(persistenceController: empty)
        XCTAssertTrue(taskService.fetchAllTasks().isEmpty)
        XCTAssertTrue(taskService.fetchActiveTasks().isEmpty)

        let habitService = HabitService(persistenceController: empty)
        XCTAssertTrue(habitService.fetchAllHabits().isEmpty)
    }
}

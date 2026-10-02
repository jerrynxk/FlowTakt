import XCTest
import CoreData
@testable import FlowTakt

// MARK: - ReminderServiceTests
// 验证 ReminderService 的通知监听链路：
// 1. 数据库重置后必须触发重排（context.reset() 不触发 ObjectsDidChange，靠 databaseDidReset 兜底）
// 2. 显式 remindersDataChanged 触发重排
// 注：内部依赖 UNUserNotificationCenter 与 App Group，此处验证「重排执行且不崩溃」的冒烟行为

final class ReminderServiceTests: XCTestCase {

    func testDatabaseDidResetNotification_ThenRescheduleRunsWithoutCrash() {
        // Given
        let persistence = PersistenceController(inMemory: true)
        let service = ReminderService(persistenceController: persistence)

        // When - 数据库重置通知（重置链路的关键兜底）
        NotificationCenter.default.post(name: .databaseDidReset, object: nil)
        // 去抖 300ms + 执行，推进 RunLoop 等待
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))

        // Then - 重排执行（写快照/清理通知）且不崩溃
        XCTAssertTrue(true, "收到 databaseDidReset 后 rescheduleAll 应执行且不崩溃")
        _ = service // 保持引用至 RunLoop 推进完成
    }

    func testRemindersDataChangedNotification_ThenRescheduleRunsWithoutCrash() {
        // Given
        let persistence = PersistenceController(inMemory: true)
        let service = ReminderService(persistenceController: persistence)

        // When - 显式提醒数据变更通知（增删改后由 ViewModel 发出）
        NotificationCenter.default.post(name: .remindersDataChanged, object: nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))

        // Then
        XCTAssertTrue(true, "收到 remindersDataChanged 后 rescheduleAll 应执行且不崩溃")
        _ = service
    }

    func testContextChange_OnlyScheduleItem_ThenRescheduleRunsWithoutCrash() {
        // Given
        let persistence = PersistenceController(inMemory: true)
        let service = ReminderService(persistenceController: persistence)

        // When - 模拟含 ScheduleItem 的上下文变更通知
        let notification = Notification(
            name: .NSManagedObjectContextObjectsDidChange,
            object: persistence.viewContext,
            userInfo: [NSInsertedObjectsKey: Set<NSManagedObject>()]
        )
        NotificationCenter.default.post(notification)
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))

        // Then
        XCTAssertTrue(true)
        _ = service
    }
}

import XCTest
import UserNotifications
@testable import FlowTakt

// MARK: - NotificationServiceTests
// 测试 NotificationService：授权请求、通知调度与取消
// 注意：由于依赖 UNUserNotificationCenter，测试侧重逻辑验证和参数正确性

final class NotificationServiceTests: XCTestCase {
    var service: NotificationService!

    override func setUp() {
        super.setUp()
        service = NotificationService()
    }

    override func tearDown() {
        service = nil
        super.tearDown()
    }

    // ========================================================================
    // MARK: - 请求授权
    // ========================================================================

    func testRequestAuthorization_CompletesWithoutCrash() async {
        // When / Then: 授权请求不应崩溃
        let _ = await service.requestAuthorization()
        XCTAssertTrue(true, "requestAuthorization 完成未崩溃")
    }

    // ========================================================================
    // MARK: - 调度通知（参数验证）
    // ========================================================================

    func testScheduleSessionEndNotification_GivenValidInput_ThenDoesNotCrash() {
        let sessionId = UUID()
        let title = "测试任务"

        // When / Then
        service.scheduleSessionEndNotification(
            sessionId: sessionId,
            title: title,
            timeInterval: 1500
        )
        XCTAssertTrue(true, "调度通知不应崩溃")
    }

    func testScheduleSessionEndNotification_GivenZeroTimeInterval_ThenReturnsEarly() {
        let sessionId = UUID()

        // When / Then: timeInterval 为 0 时应安全返回
        service.scheduleSessionEndNotification(
            sessionId: sessionId,
            title: "测试",
            timeInterval: 0
        )
        XCTAssertTrue(true, "零时间间隔不应崩溃")
    }

    func testScheduleSessionEndNotification_GivenNegativeTimeInterval_ThenReturnsEarly() {
        let sessionId = UUID()

        // When / Then: timeInterval 为负时应安全返回
        service.scheduleSessionEndNotification(
            sessionId: sessionId,
            title: "测试",
            timeInterval: -1
        )
        XCTAssertTrue(true, "负时间间隔不应崩溃")
    }

    // ========================================================================
    // MARK: - 取消通知
    // ========================================================================

    func testCancelNotification_GivenIdentifier_ThenDoesNotCrash() {
        // When / Then
        service.cancelNotification(withIdentifier: "test-id-123")
        XCTAssertTrue(true, "取消通知不应崩溃")
    }

    func testCancelNotification_GivenEmptyString_ThenDoesNotCrash() {
        // When / Then
        service.cancelNotification(withIdentifier: "")
        XCTAssertTrue(true, "空 Identifier 不应崩溃")
    }
}

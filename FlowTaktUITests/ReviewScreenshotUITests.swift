import XCTest

/// 审核素材截图：遍历主要页面并保存 PNG 到 /tmp/flowtakt-shots/（C2）。
final class ReviewScreenshotUITests: XCTestCase {

    @MainActor
    func testCaptureMainScreens() throws {
        let app = XCUIApplication()
        // 重置为竖屏（避免前序测试导致模拟器旋转使 TabBar 不在底部）
        XCUIDevice.shared.orientation = .portrait

        app.launch()

        // 处理首次启动的系统弹窗（通知权限等），避免阻塞 TabBar 查询
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allowButton = springboard.buttons["允许"]
        if allowButton.waitForExistence(timeout: 2) {
            allowButton.tap()
        }
        let dir = "/tmp/flowtakt-shots"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        // 1. 专注页
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10), "App 应完成启动并显示 TabBar")
        Thread.sleep(forTimeInterval: 3)
        save("01-focus")

        // 1b. 专注 → 正计时（用户反馈 2026-11-19：正计时入口并入专注主面板）
        let stopwatchEntry = app.buttons["switchToStopwatchButton"]
        XCTAssertTrue(stopwatchEntry.waitForExistence(timeout: 5),
                      "专注主面板应提供「正计时」入口")
        stopwatchEntry.tap()
        Thread.sleep(forTimeInterval: 2)
        save("01b-focus-stopwatch")
        let pomodoroEntry = app.buttons["switchToPomodoroButton"]
        XCTAssertTrue(pomodoroEntry.waitForExistence(timeout: 5),
                      "正计时面板应能切回番茄钟")
        pomodoroEntry.tap()
        Thread.sleep(forTimeInterval: 1)

        // 2. 计划 → 任务
        app.tabBars.buttons["计划"].tap()
        Thread.sleep(forTimeInterval: 2)
        save("02-plan-task")

        // 3. 计划 → 日程
        app.buttons["日程"].tap()
        Thread.sleep(forTimeInterval: 2)
        save("03-plan-calendar")

        // 4. 习惯
        app.tabBars.buttons["习惯"].tap()
        Thread.sleep(forTimeInterval: 2)
        save("04-habit")

        // 5. 统计
        app.tabBars.buttons["统计"].tap()
        Thread.sleep(forTimeInterval: 2)
        save("05-stats")

        // 6. 设置
        app.tabBars.buttons["设置"].tap()
        Thread.sleep(forTimeInterval: 2)
        save("06-settings")
    }

    private func save(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        try? shot.pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/flowtakt-shots/\(name).png"))
    }
}

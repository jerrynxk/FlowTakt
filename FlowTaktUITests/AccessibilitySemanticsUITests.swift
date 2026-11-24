import XCTest

/// 无障碍语义回归（2026-11-02）
///
/// 覆盖本轮补齐的三类缺口，均以**可断言的语义**为判据（XCUITest 读不到 heading trait，
/// 故用「合并后的 label 内容」与「isEnabled」代替）：
/// 1. 计时圆环 label 必须同时含阶段名与剩余时间（此前只有「剩余 X 分 Y 秒」，阶段语境丢失）
/// 2. 任务分解圆环 label 必须是完整汇总句（此前修饰挂在 Shape 上，完全不生效）
/// 3. 未解锁成就徽章必须不是可点按钮（此前是可点但无反馈的假交互）
final class AccessibilitySemanticsUITests: XCTestCase {

    /// 启动 App 并等待 TabBar；顺带关闭首次启动的系统权限弹窗
    @MainActor
    private func launchApp() throws -> XCUIApplication {
        let app = XCUIApplication()
        // 重置为竖屏（避免前序测试导致模拟器旋转使 TabBar 不在底部）
        XCUIDevice.shared.orientation = .portrait
        app.launch()

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allowButton = springboard.buttons["允许"]
        if allowButton.waitForExistence(timeout: 2) {
            allowButton.tap()
        }

        let tabBarAppeared = app.tabBars.firstMatch.waitForExistence(timeout: 10)
        if !tabBarAppeared {
            try? XCUIScreen.main.screenshot().pngRepresentation
                .write(to: URL(fileURLWithPath: "/tmp/ui-fail-\(name).png"))
        }
        XCTAssertTrue(tabBarAppeared, "App 应完成启动并显示 TabBar")
        return app
    }

    /// 专注页计时圆环：label = 「专注，剩余 25 分 0 秒」
    @MainActor
    func testFocusTimerLabelIncludesPhase() throws {
        let app = try launchApp()

        let timer = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "专注", "剩余"))
            .firstMatch
        XCTAssertTrue(
            timer.waitForExistence(timeout: 5),
            "计时圆环的无障碍标签应含阶段名「专注」与「剩余 …」时间（2026-11-02 修复前只有剩余时间）"
        )
    }

    /// 统计页任务分解圆环：label 含「任务分解」与「共 N 个任务」
    @MainActor
    func testTaskBreakdownHasAggregatedLabel() throws {
        let app = try launchApp()

        app.tabBars.buttons["统计"].tap()

        let breakdown = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "任务分解", "个任务"))
            .firstMatch

        // 该卡片位于统计页中部，必要时上滑一次
        if !breakdown.waitForExistence(timeout: 4) {
            app.swipeUp()
        }
        XCTAssertTrue(
            breakdown.waitForExistence(timeout: 5),
            "任务分解圆环应输出聚合文案「任务分解，…，共 N 个任务」（2026-11-02 修复前 Shape 上的 label 不生效）"
        )
    }

    /// 成就页未解锁徽章：不应被声明为按钮（而非可点但无反馈的假交互）
    @MainActor
    func testLockedAchievementBadgesAreNotButtons() throws {
        let app = try launchApp()

        app.tabBars.buttons["统计"].tap()
        // 顶部分段控件切到「成就」
        let achievementsSegment = app.buttons["成就"]
        XCTAssertTrue(achievementsSegment.waitForExistence(timeout: 4), "统计页应有「成就」分段")
        achievementsSegment.tap()

        let locked = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "未解锁"))
            .firstMatch
        XCTAssertTrue(locked.waitForExistence(timeout: 5), "成就页应存在未解锁徽章")

        // 未解锁徽章不再声明为按钮（读屏按静态文本播报「初次专注，未解锁」）。
        // 注：不用 .disabled() —— 实测会对整块徽章二次降透明度，文字几乎不可读。
        let lockedButtons = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", "未解锁"))
        XCTAssertEqual(
            lockedButtons.count, 0,
            "未解锁成就徽章不应被声明为按钮（2026-11-02 修复前为可点但 handleTap 直接 return 的假按钮）"
        )
    }
}

import XCTest

/// UI 自动化验证（2026-11-01）：
/// 1. 专注 / 习惯 / 统计 三个顶部标签支持「左右滑动切换」，且边界夹紧不回环；
/// 2. 页面顶部下拉不会触发标签切换 / 崩溃。弹性在 AppDelegate 中通过
///    `UIScrollView.appearance().bounces = false` **全局**禁用，覆盖所有 List / ScrollView /
///    模态与抽屉内滚动容器（专注、日程周视图、计时、习惯热力图、成就、统计等无一例外）。
///
/// 关键判定手段：分段控件（UISegmentedControl）的 `value` 即当前选中段标题，
/// 通过 XCUITest 读取该值即可断言滑动是否真正切换了选中态。
final class SwipeAndBounceUITests: XCTestCase {

    // MARK: - 工具

    @MainActor
    private func handlePermissionAlertIfNeeded(_ app: XCUIApplication) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["允许"]
        if allow.waitForExistence(timeout: 2) {
            allow.tap()
        }
    }

    /// 在屏幕顶部区域做一段横向滑动（避开热力图等内部横向滚动区，
    /// 也避免误触竖向 ScrollView），仅用于触发外层 VStack 的左右滑手势。
    private func horizontalSwipe(in app: XCUIApplication, toLeft: Bool) {
        let yRatio: CGFloat = 0.08 // 紧贴顶部分段控件区域
        let startX: CGFloat = toLeft ? 0.82 : 0.18
        let endX: CGFloat   = toLeft ? 0.18 : 0.82
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: startX, dy: yRatio))
        let end   = app.coordinate(withNormalizedOffset: CGVector(dx: endX,   dy: yRatio))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    /// 轮询等待顶部分段控件（accessibilityIdentifier = "topTabPicker"）的选中按钮变为 expected，
    /// 最长 2s，否则失败。判定依据为分段按钮的 isSelected 状态（不依赖 value）。
    private func assertSegment(
        in app: XCUIApplication,
        equals expected: String,
        _ message: String = "",
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let seg = app.segmentedControls["topTabPicker"]
        var actual: String?
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if seg.exists {
                for i in 0..<seg.buttons.count {
                    let b = seg.buttons.element(boundBy: i)
                    if b.isSelected {
                        actual = b.label
                        break
                    }
                }
            }
            if actual == expected { return }
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTFail(
            "\(message) 期望顶部分段选中「\(expected)」，实际「\(String(describing: actual))」",
            file: file,
            line: line
        )
    }

    // MARK: - 1. 三页左右滑切换顶部标签

    @MainActor
    func testSwipeSwitchesAllTopTabs() throws {
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        app.launch()

        handlePermissionAlertIfNeeded(app)
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10), "应完成启动并显示 TabBar")

        // ---- 专注页：专注 / 短休息 / 长休息 ----
        tabBar.buttons["专注"].tap()
        assertSegment(in: app, equals: "专注", "专注页默认")
        horizontalSwipe(in: app, toLeft: true);  assertSegment(in: app, equals: "短休息", "专注页左滑1")
        horizontalSwipe(in: app, toLeft: true);  assertSegment(in: app, equals: "长休息", "专注页左滑2")
        horizontalSwipe(in: app, toLeft: true);  assertSegment(in: app, equals: "长休息", "专注页左滑到底夹紧")
        horizontalSwipe(in: app, toLeft: false); assertSegment(in: app, equals: "短休息", "专注页右滑1")
        horizontalSwipe(in: app, toLeft: false); assertSegment(in: app, equals: "专注", "专注页右滑2")
        horizontalSwipe(in: app, toLeft: false); assertSegment(in: app, equals: "专注", "专注页右滑到底夹紧")

        // ---- 计划页：任务 / 日程 ----
        // 2026-11-02 新增：计划页支持整页左右滑动切换子页
        tabBar.buttons["计划"].tap()
        assertSegment(in: app, equals: "任务", "计划页默认")
        horizontalSwipe(in: app, toLeft: true);  assertSegment(in: app, equals: "日程", "计划页左滑")
        horizontalSwipe(in: app, toLeft: true);  assertSegment(in: app, equals: "日程", "计划页左滑到底夹紧")
        horizontalSwipe(in: app, toLeft: false); assertSegment(in: app, equals: "任务", "计划页右滑")
        horizontalSwipe(in: app, toLeft: false); assertSegment(in: app, equals: "任务", "计划页右滑到底夹紧")

        // ---- 习惯页：习惯 / 热力图 ----
        // 2026-11-22：计时段已移除，习惯页现为两段
        tabBar.buttons["习惯"].tap()
        assertSegment(in: app, equals: "习惯", "习惯页默认")
        horizontalSwipe(in: app, toLeft: true);  assertSegment(in: app, equals: "热力图", "习惯页左滑")
        horizontalSwipe(in: app, toLeft: true);  assertSegment(in: app, equals: "热力图", "习惯页左滑到底夹紧")
        horizontalSwipe(in: app, toLeft: false); assertSegment(in: app, equals: "习惯", "习惯页右滑")
        horizontalSwipe(in: app, toLeft: false); assertSegment(in: app, equals: "习惯", "习惯页右滑到底夹紧")

        // ---- 统计页：统计 / 成就 ----
        tabBar.buttons["统计"].tap()
        assertSegment(in: app, equals: "统计", "统计页默认")
        horizontalSwipe(in: app, toLeft: true);  assertSegment(in: app, equals: "成就", "统计页左滑")
        horizontalSwipe(in: app, toLeft: true);  assertSegment(in: app, equals: "成就", "统计页左滑到底夹紧")
        horizontalSwipe(in: app, toLeft: false); assertSegment(in: app, equals: "统计", "统计页右滑")
        horizontalSwipe(in: app, toLeft: false); assertSegment(in: app, equals: "统计", "统计页右滑到底夹紧")
    }

    // MARK: - 2. 下拉固定 / 稳定

    /// 短页（专注页）：内容与视口等高时，**向上滑**也完全不应产生位移。
    ///
    /// 背景（2026-11-02 用户反馈"往上滑会自己跳下来"）：
    /// 该页内容被 `minHeight` 撑到刚好一屏，若滚动容器仍允许拖动（`alwaysBounceVertical` 漏扫），
    /// 上滑只会产生橡皮筋位移、松手必回原位，观感即"滑一下又跳回去"。
    /// 现由 `.scrollBounceBehavior(.basedOnSize)` 在内容不超过视口时彻底禁止拖动，
    /// 本用例锁定该行为：上滑后顶部控件位置必须纹丝不动。
    @MainActor
    func testFocusPageFixedOnSwipeUp() throws {
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        app.launch()

        handlePermissionAlertIfNeeded(app)
        app.tabBars.buttons["专注"].tap()

        // 注意：断言对象必须是 ScrollView **内部**的元素。
        // 2026-11-02 修正 —— 此前用的是顶部分段控件，它位于 ScrollView 之外的 VStack 首项，
        // 内容怎么滚它都不会动，导致用例恒绿、真机问题被漏检。
        let title = app.staticTexts["focusLargeTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5), "专注页应有大标题")

        let yBefore = title.frame.minY
        // 由下往上滑（模拟用户「上滑」）
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78))
        let end   = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.32))
        start.press(forDuration: 0.1, thenDragTo: end)
        Thread.sleep(forTimeInterval: 0.6)

        let yAfter = title.frame.minY
        XCTAssertLessThanOrEqual(
            abs(yAfter - yBefore), 2.0,
            "专注页上滑后内容位置应不变（内容不超一屏时不可拖动），before=\(yBefore) after=\(yAfter)"
        )
    }

    /// 短页（专注页）：内容不足一屏，顶部向下拉后顶部分段控件位置应完全不动（拉不动）。
    @MainActor
    func testShortPageFixedOnPullDown() throws {
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        app.launch()

        handlePermissionAlertIfNeeded(app)
        app.tabBars.buttons["专注"].tap()

        // 同 testFocusPageFixedOnSwipeUp：断言 ScrollView 内部元素（分段控件在滚动容器之外，
        // 用它做断言永远测不出位移 —— 2026-11-02 修正）
        let title = app.staticTexts["focusLargeTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5), "专注页应有大标题")

        let yBefore = title.frame.minY
        // 在顶部向下拉（模拟「下拉」手势）
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08))
        let end   = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.40))
        start.press(forDuration: 0.1, thenDragTo: end)
        Thread.sleep(forTimeInterval: 0.5)

        let yAfter = title.frame.minY
        XCTAssertLessThanOrEqual(
            abs(yAfter - yBefore), 2.0,
            "专注页（短页）下拉后内容位置应不变（拉不动），before=\(yBefore) after=\(yAfter)"
        )
    }

    /// 长页（统计页）：内容超过一屏，顶部多次下拉不应切换标签 / 崩溃（弹性已禁用）。
    @MainActor
    func testLongPageStableOnPullDown() throws {
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        app.launch()

        handlePermissionAlertIfNeeded(app)
        app.tabBars.buttons["统计"].tap()

        let seg = app.segmentedControls.firstMatch
        XCTAssertTrue(seg.waitForExistence(timeout: 5), "统计页应有顶部分段控件")
        assertSegment(in: app, equals: "统计", "统计页默认")

        // 连续在顶部向下拉，验证不会误触标签切换、不崩溃
        for _ in 0..<3 {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.10))
            let end   = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
            start.press(forDuration: 0.1, thenDragTo: end)
            Thread.sleep(forTimeInterval: 0.3)
        }
        assertSegment(in: app, equals: "统计", "统计页顶部下拉后选中态应保持「统计」")
    }

    // MARK: - 3. 用户点名的下拉页面：日程周视图 / 计时页 下拉不崩、不跳

    /// 日程周视图（List 容器）与正计时页（专注 tab 内，ScrollView 容器）顶部多次下拉：
    /// 应不崩溃、不切走当前 Tab（弹性全局已禁用）。
    /// 2026-11-22：计时页从习惯 tab 移除，正计时统一收敛到专注页。
    @MainActor
    func testScheduleWeekAndTimerStableOnPullDown() throws {
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        app.launch()

        handlePermissionAlertIfNeeded(app)
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10), "应完成启动并显示 TabBar")

        // ---- 计划 → 日程 → 周视图 ----
        // PlanView 默认进入「任务」子页；先切到「日程」子页（ScheduleView），再切到「周视图」。
        tabBar.buttons["计划"].tap()
        Thread.sleep(forTimeInterval: 0.3)
        let calendarSeg = app.buttons["日程"]
        XCTAssertTrue(calendarSeg.waitForExistence(timeout: 5), "计划页应有「日程」子分段")
        calendarSeg.tap()
        Thread.sleep(forTimeInterval: 0.3)

        let weekBtn = app.buttons["周视图"]
        XCTAssertTrue(weekBtn.waitForExistence(timeout: 5), "日程页应有「周视图」分段")
        weekBtn.tap()
        Thread.sleep(forTimeInterval: 0.3)

        for _ in 0..<3 {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.20))
            let end   = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
            start.press(forDuration: 0.1, thenDragTo: end)
            Thread.sleep(forTimeInterval: 0.3)
        }
        XCTAssertTrue(tabBar.buttons["计划"].isSelected, "日程周视图顶部下拉后不应切走「计划」Tab")
        XCTAssertTrue(app.exists, "日程周视图顶部下拉后 App 不应崩溃")

        // ---- 专注 → 正计时 ----
        // 2026-11-22：计时入口统一收敛到专注页（习惯 tab 计时段已移除）
        tabBar.buttons["专注"].tap()
        let stopwatchEntry = app.buttons["switchToStopwatchButton"]
        XCTAssertTrue(stopwatchEntry.waitForExistence(timeout: 5), "专注页应有正计时入口")
        stopwatchEntry.tap()
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertTrue(app.staticTexts["stopwatchLargeTitle"].waitForExistence(timeout: 4),
                      "应进入正计时页")

        for _ in 0..<3 {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.20))
            let end   = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
            start.press(forDuration: 0.1, thenDragTo: end)
            Thread.sleep(forTimeInterval: 0.3)
        }
        XCTAssertTrue(tabBar.buttons["专注"].isSelected, "正计时页顶部下拉后不应切走「专注」Tab")
        XCTAssertTrue(app.exists, "正计时页顶部下拉后 App 不应崩溃")
    }
}

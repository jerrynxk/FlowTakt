import XCTest

/// 用户反馈三项修复的 UI 自动化验证（2026-11-17）
///
/// 覆盖：
/// 1. 提前结束番茄钟：净专注时长计入统计，但不算完成番茄 / 不发积分
/// 2. 正计时：暂停后净计时冻结、显示「已暂停」与「暂停段不计入时长」，继续后接着走，
///    停止后时长计入统计页「专注时长」（番茄数不变）
/// 3. 手动同步：如实反馈真实结果（默认开关关闭 → 显示「请先开启 iCloud 同步开关」），
///    不再无条件显示已被移除的假说明「同步请求已发送」
///
/// 判据全部取 UI 可观察状态（无障碍 label / 静态文案 / accessibilityIdentifier），
/// 不读内部数据库。截图写到 /tmp/flowtakt-ui-verify/ 供人工复核。
final class UserFeedbackVerificationUITests: XCTestCase {

    private let shotDir = "/tmp/flowtakt-ui-verify"

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        try? FileManager.default.createDirectory(atPath: shotDir, withIntermediateDirectories: true)
    }

    // MARK: - Helpers

    /// 启动 App 并处理首次启动权限弹窗，等待 TabBar
    @MainActor
    private func launchApp() throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["允许", "Allow"] {
            let button = springboard.buttons[label]
            if button.waitForExistence(timeout: 2) { button.tap() }
        }
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 12), "App 应完成启动并显示 TabBar")
        return app
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try? data.write(to: URL(fileURLWithPath: "\(shotDir)/\(name).png"))
    }

    /// 切换到指定主 Tab（优先 TabBar 按钮，兼容中文/英文）
    @MainActor
    private func switchTab(_ app: XCUIApplication, _ names: [String]) {
        for name in names {
            let button = app.tabBars.buttons[name]
            if button.waitForExistence(timeout: 2) {
                button.tap()
                return
            }
        }
        XCTFail("未找到主 Tab：\(names)")
    }

    /// 在长 Form 中滚动查找按钮（元素只有进入可视区域才被 SwiftUI 挂载到可访问性树）
    @MainActor
    private func findButtonScrolling(_ app: XCUIApplication,
                                     _ predicate: NSPredicate,
                                     maxSwipes: Int = 10) -> XCUIElement? {
        let matched = app.buttons.matching(predicate).firstMatch
        for _ in 0...maxSwipes {
            if matched.exists && matched.isHittable { return matched }
            app.swipeUp()
            Thread.sleep(forTimeInterval: 0.3)
        }
        return matched.exists ? matched : nil
    }

    // MARK: - 1. 提前结束番茄钟：时长计入、番茄不计入

    /// 启动专注 → 等若干秒 → 点停止 → 统计页应显示「专注时长>0」但「完成番茄=0」
    @MainActor
    func testEarlyCompletion_PreservesDurationButNotPomodoro() throws {
        let app = try launchApp()
        switchTab(app, ["专注", "Focus"])

        // 主控制按钮：无障碍 label = 开始 / Start
        let start = app.buttons.matching(
            NSPredicate(format: "label == '开始' OR label == 'Start'")
        ).firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 5), "专注页应有开始按钮")
        start.tap()

        // 运行几秒，制造可观察的净专注时长（无需走完整个番茄，正是反馈场景）
        Thread.sleep(forTimeInterval: 4)
        shot(app, "01-early-before-stop")

        // 停止按钮：无障碍 label = 停止 / Stop
        let stop = app.buttons.matching(
            NSPredicate(format: "label == '停止' OR label == 'Stop'")
        ).firstMatch
        XCTAssertTrue(stop.waitForExistence(timeout: 3), "计时中应出现停止按钮")
        stop.tap()
        Thread.sleep(forTimeInterval: 1)
        shot(app, "02-early-after-stop")

        // 统计页：完成番茄数应为 0；专注时长行应出现（>0）
        switchTab(app, ["统计", "Stats"])
        Thread.sleep(forTimeInterval: 1)

        let overview = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS '今日概览' OR label CONTAINS \"Today's Overview\"")
        ).firstMatch
        XCTAssertTrue(overview.waitForExistence(timeout: 5), "统计页应有今日概览卡")
        let overviewLabel = overview.label
        shot(app, "03-early-stats")

        // 完成番茄为 0（提前结束不算番茄）
        let zeroPomodoro = overviewLabel.contains("0 个") || overviewLabel.contains("0 pomodoro")
        XCTAssertTrue(zeroPomodoro, "提前结束不应增加完成番茄数；实际概览：\(overviewLabel)")

        // 「专注时长」行出现（todayDuration > 0 时才渲染）
        let hasDuration = overviewLabel.contains("分钟") || overviewLabel.contains("小时")
            || overviewLabel.contains("min") || overviewLabel.contains("h")
        XCTAssertTrue(hasDuration, "提前结束的净时长应计入统计页专注时长；实际概览：\(overviewLabel)")
    }

    // MARK: - 2. 正计时：暂停冻结 / 继续 / 计入总和

    @MainActor
    func testTimeRecord_PauseResumeAndCountedInTotals() throws {
        let app = try launchApp()
        // 2026-11-22：计时入口统一收敛到「专注」页正计时（习惯 tab 计时段已移除）
        switchTab(app, ["专注", "Focus"])

        // 番茄钟标题行的「正计时」入口（冷启动 idle 态直接切入，无确认弹窗）
        let stopwatchEntry = app.buttons["switchToStopwatchButton"]
        XCTAssertTrue(stopwatchEntry.waitForExistence(timeout: 4), "专注页应有正计时入口")
        stopwatchEntry.tap()
        Thread.sleep(forTimeInterval: 0.5)

        let startTimer = app.buttons["startTimeRecordButton"]
        XCTAssertTrue(startTimer.waitForExistence(timeout: 4), "计时页应有开始计时按钮")
        startTimer.tap()
        Thread.sleep(forTimeInterval: 2)
        shot(app, "04-timer-running")

        let pauseResume = app.buttons["pauseResumeTimeRecordButton"]
        XCTAssertTrue(pauseResume.waitForExistence(timeout: 3), "计时中应出现暂停按钮")
        XCTAssertEqual(pauseResume.label, "暂停", "计时中暂停按钮 label 应为暂停（或本地化对应）")
        pauseResume.tap()
        Thread.sleep(forTimeInterval: 0.5)

        // 暂停态文案
        let pausedText = app.staticTexts.matching(
            NSPredicate(format: "label == '已暂停' OR label == 'Paused'")
        ).firstMatch
        XCTAssertTrue(pausedText.waitForExistence(timeout: 3), "暂停后应显示「已暂停」")
        let noteText = app.staticTexts.matching(
            NSPredicate(format: "label == '暂停段不计入时长' OR label == 'Paused time is not counted'")
        ).firstMatch
        XCTAssertTrue(noteText.waitForExistence(timeout: 3), "暂停后应提示「暂停段不计入时长」")
        XCTAssertEqual(pauseResume.label, "恢复", "暂停后按钮 label 应切换为恢复")
        shot(app, "05-timer-paused")

        // 净计时冻结：暂停期间经过时间不增长
        // 2026-11-22：正计时（embedded）的大计时卡是无障碍合并元素，label 形如
        // 「正计时，已计时 X，今日专注时长 …」，以「正计时」开头；独立页以「已计时」开头。
        // 用 CONTAINS 兼容两种形态（BEGINSWITH '已计时' 会漏掉 embedded 形态）。
        let elapsed = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '已计时' OR label CONTAINS 'Timed'")
        ).firstMatch
        XCTAssertTrue(elapsed.waitForExistence(timeout: 3), "应有已计时无障碍标签")
        let frozen = elapsed.label
        Thread.sleep(forTimeInterval: 2.5)
        let stillFrozen = app.staticTexts.matching(
            NSPredicate(format: "label == %@", frozen)
        ).firstMatch
        XCTAssertTrue(stillFrozen.exists || elapsed.label == frozen,
                      "暂停期间净计时应冻结；原值=\(frozen) 现值=\(elapsed.label)")

        // 继续 + 停止
        pauseResume.tap()
        XCTAssertEqual(pauseResume.label, "暂停", "继续后按钮 label 应切回暂停")
        Thread.sleep(forTimeInterval: 2)
        shot(app, "06-timer-resumed")
        app.buttons["stopTimeRecordButton"].tap()
        Thread.sleep(forTimeInterval: 1)
        XCTAssertTrue(startTimer.waitForExistence(timeout: 3), "停止后应回到开始计时状态")

        // 统计页「专注时长」应因正计时而出现（>0）
        switchTab(app, ["统计", "Stats"])
        Thread.sleep(forTimeInterval: 1)
        let overview = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS '今日概览' OR label CONTAINS \"Today's Overview\"")
        ).firstMatch
        XCTAssertTrue(overview.waitForExistence(timeout: 5))
        let label = overview.label
        shot(app, "07-timer-stats")
        let hasDuration = label.contains("分钟") || label.contains("小时")
            || label.contains("min") || label.contains("h")
        XCTAssertTrue(hasDuration, "正计时时长应计入统计页；实际概览：\(label)")
    }

    // MARK: - 3. 手动同步：真实结果反馈（消除假说明）

    @MainActor
    func testManualSync_ShowsTruthfulOutcome() throws {
        let app = try launchApp()
        switchTab(app, ["设置", "Settings"])

        // 设置页 Form 较长，「立即同步」在同步分区内，需滚动进入可视区域才被挂载
        guard let syncNow = findButtonScrolling(
            app,
            NSPredicate(format: "label == '立即同步' OR label == 'Sync Now'")
        ) else {
            shot(app, "08-sync-button-not-found")
            XCTFail("设置页应有立即同步按钮（滚动后仍未找到）")
            return
        }
        syncNow.tap()
        Thread.sleep(forTimeInterval: 0.8)
        shot(app, "08-sync-outcome")

        // 用户反馈 2026-11-19：iCloud 同步已改为**默认开启**，因此不再必然出现
        // 「请先开启」提示。核心不变的是「必须如实反馈真实结果」——断言命中任一真实结果文案，
        // 并且绝不允许出现旧的「同步请求已发送」假说明。
        //
        // 注意：文案里含英文撇号（Other devices' updates），**不能**直接拼进 NSPredicate 的
        // format 字符串 —— 单引号是 NSPredicate 的字符串定界符，会把表达式截断成非法语法
        // 并抛异常（XCUITest 无法捕获，直接崩测试进程）。统一用 %@ 数组参数传入。
        let truthfulLabels = [
            "请先开启 iCloud 同步开关",
            "Please enable iCloud Sync first",
            "iCloud 账户不可用，请登录 iCloud 后重试",
            "iCloud account unavailable — sign in and retry",
            "无本地变更；其它设备的更新会自动导入",
            "No local changes. Other devices' updates arrive automatically.",
            "本地变更已保存，正在上传至 iCloud",
            "Local changes saved — uploading to iCloud",
            "同步已开启但尚未连接，请稍候或重新打开 App",
            "Sync is on but not connected yet — please wait or reopen the app"
        ]
        let truthfulPredicate = NSPredicate(
            format: "label IN %@ OR label BEGINSWITH %@ OR label BEGINSWITH %@",
            truthfulLabels, "同步失败", "Sync failed"
        )
        let truthful = app.staticTexts.matching(truthfulPredicate).firstMatch
        XCTAssertTrue(truthful.waitForExistence(timeout: 5),
                      "同步结果必须如实反馈（账户不可用/无本地变更/已保存之一），而非笼统或虚假提示")

        // 旧假说明已移除，UI 不应再出现
        let fakeMessage = app.staticTexts.matching(
            NSPredicate(format: "label == '同步请求已发送' OR label CONTAINS 'Sync request sent'")
        ).firstMatch
        XCTAssertFalse(fakeMessage.exists, "不应再出现「同步请求已发送」假说明")
    }

    // MARK: - 4. 按标签统计五档切换（2026-11-22 用户反馈）
    /// 覆盖：五档分段存在 → 切「自定义」弹日期面板 → 取消不改数据 → 常驻入口可重开
    @MainActor
    func testTagDurationCard_FiveRangesAndCustomPanel() throws {
        let app = try launchApp()
        switchTab(app, ["统计", "Stats"])

        let picker = app.segmentedControls["tagRangePicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 8), "按标签统计应有五档分段控件")
        XCTAssertEqual(picker.buttons.count, 5, "档位应为 全部/年/月/周/自定义 五档")

        // 切到「自定义」应自动弹出日期面板（先用默认 30 天落地数据）
        let customSegment = picker.buttons.matching(
            NSPredicate(format: "label == '自定义' OR label == 'Custom'")
        ).firstMatch
        XCTAssertTrue(customSegment.exists, "应有自定义档")
        customSegment.tap()

        let rangeTitle = app.staticTexts.matching(
            NSPredicate(format: "label == '自定义范围' OR label == 'Custom Range'")
        ).firstMatch
        XCTAssertTrue(rangeTitle.waitForExistence(timeout: 5), "选自定义应弹出日期范围面板")
        shot(app, "10-tag-custom-panel")

        // 取消只关面板，不改数据
        let cancel = app.buttons.matching(
            NSPredicate(format: "label == '取消' OR label == 'Cancel'")
        ).firstMatch
        XCTAssertTrue(cancel.exists)
        cancel.tap()

        // 已选自定义后，常驻日期入口仍可再次打开面板（分段同值点击不触发 onChange 的补偿）
        let entry = app.buttons.matching(
            NSPredicate(format: "label CONTAINS '自定义范围' OR label CONTAINS 'Custom Range'")
        ).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 3), "自定义档下应有常驻日期入口")
        entry.tap()
        XCTAssertTrue(rangeTitle.waitForExistence(timeout: 5), "点常驻入口应能重新打开日期面板")
    }
}

import XCTest

/// 崩溃修复 UI 自动化回归（2026-10-02 第二轮线上崩溃排查）
///
/// 覆盖三条曾在线上崩溃的用户可复现路径：
/// 1. 计时页记录列表多选删除（`TimeRecordView.deleteRecords` 数组越界）
/// 2. 设置 → 导出数据（CSV，含孤儿 HabitRecord 时 `r.habit.name` 强解包）
/// 3. 设置 → 备份数据（JSON，含孤儿 HabitRecord 时 `record.habit.id` 强解包）
///
/// 另含习惯删除链路（验证显式级联删除后 UI 正常）。
///
/// 判定标准：App 进程存活（未崩溃）且关键 UI 元素存在。
/// 崩溃会导致 `app.state` 变为 `.notRunning`，直接判定失败。
final class CrashRegressionUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// 断言 App 仍在前台运行（若崩溃则 process 已退出）。
    private func assertStillRunning(_ app: XCUIApplication,
                                   _ step: String,
                                   timeout: TimeInterval = 3) {
        let predicate = NSPredicate(format: "state == %d", XCUIApplication.State.runningForeground.rawValue)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: app)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(result, .completed,
                       "「\(step)」后 App 应仍在前台运行；若崩溃说明该路径仍有缺陷")
    }

    /// 切换到指定主 Tab。
    private func switchTab(_ app: XCUIApplication, tabName: String) {
        let tab = app.tabBars.buttons[tabName]
        if tab.waitForExistence(timeout: 3) {
            tab.tap()
        } else if app.buttons[tabName].exists {
            app.buttons[tabName].tap()
        }
    }

    /// 在设置页滚动查找按钮。设置页 Form 很长，导出/备份入口在底部，
    /// 首次查询通常需要多次上滑才能进入可见区域。
    private func scrollToButton(_ app: XCUIApplication, identifier: String,
                                maxSwipes: Int = 8) -> XCUIElement {
        let button = app.buttons[identifier]
        var attempts = 0
        while attempts < maxSwipes {
            if button.exists && button.isHittable { return button }
            if button.exists && !button.isHittable {
                button.tap()   // 存在即可点（可能自动滚动）
                return button
            }
            app.swipeUp()
            attempts += 1
            Thread.sleep(forTimeInterval: 0.4)
        }
        return button
    }

    // MARK: - 1. 计时页：开始记录 + 多条记录 + 滑动删除

    /// 覆盖 P0-4：计时页记录列表的删除链路。
    /// 原实现在多选删除时 `recordsForDate[index]` 越界崩溃（Fatal error: Index out of range）。
    /// 本测试创建多条记录并逐条左滑删除，验证不崩溃。
    @MainActor
    func testTimeRecordCreateAndDelete_DoesNotCrash() throws {
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "App 应正常启动")

        // 2026-11-22：计时入口统一收敛到「专注」页正计时（习惯 tab 计时段已移除）
        switchTab(app, tabName: "专注")
        let stopwatchEntry = app.buttons["switchToStopwatchButton"]
        if stopwatchEntry.waitForExistence(timeout: 4) { stopwatchEntry.tap() }
        Thread.sleep(forTimeInterval: 0.5)

        // 记录 2 次（每次 start → stop），产生多条当日记录
        // 使用无障碍标识精确定位（源码已设 accessibilityIdentifier）
        for _ in 0..<2 {
            let startButton = app.buttons["startTimeRecordButton"]
            guard startButton.waitForExistence(timeout: 5) else { break }
            startButton.tap()
            assertStillRunning(app, "点击开始计时")

            // 等待停止按钮出现（表示已进入计时中状态）
            let stopButton = app.buttons["stopTimeRecordButton"]
            XCTAssertTrue(stopButton.waitForExistence(timeout: 5), "应出现停止计时按钮")
            Thread.sleep(forTimeInterval: 1.2)
            stopButton.tap()
            Thread.sleep(forTimeInterval: 0.8)
        }

        assertStillRunning(app, "计时记录创建")

        // 2026-11-22：嵌入形态记录列表改为每行的删除按钮（原独立页靠左滑 onDelete）。
        // 反复点第一条删除按钮，覆盖多轮删除后数组收缩场景，验证不崩溃。
        for round in 0..<3 {
            let deleteButtons = app.buttons.matching(
                NSPredicate(format: "label BEGINSWITH '删除'")
            )
            guard deleteButtons.count > 0 else { break }
            deleteButtons.element(boundBy: 0).tap()
            Thread.sleep(forTimeInterval: 0.6)
            assertStillRunning(app, "第 \(round + 1) 次删除记录")
        }

        assertStillRunning(app, "正计时删除流程完成")
    }

    // MARK: - 2. 设置 → 导出数据（CSV）

    /// 覆盖 P0-1：设置页「导出数据」触发 CSV 导出。
    /// 数据库中可能存在 `habit == nil` 的孤儿 HabitRecord（CloudKit 不支持级联删除），
    /// 原实现 `r.habit.name` 会 EXC_BAD_ACCESS。
    @MainActor
    func testExportCSVFromSettings_DoesNotCrash() throws {
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "App 应正常启动")

        switchTab(app, tabName: "设置")

        // 滚动到「导出数据」按钮（源码已设 accessibilityIdentifier）
        let exportButton = scrollToButton(app, identifier: "exportCSVButton")
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5),
                      "设置页应存在「导出数据」入口（已滚动查找）")

        // 滚动到该按钮并点击
        exportButton.tap()
        Thread.sleep(forTimeInterval: 2.5)

        // 导出成功后应弹出系统分享面板；关闭它
        let shareSheet = app.otherElements["ActivityListView"]
        if shareSheet.exists {
            // 关闭分享面板（竞态修复同 JSON 备份用例：面板动画期间需等稳定再点）
            Thread.sleep(forTimeInterval: 1.0)
            let closeButton = app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] %@", "关闭")
            ).firstMatch
            if closeButton.exists && closeButton.isHittable {
                closeButton.tap()
            } else if app.buttons["取消"].exists && app.buttons["取消"].isHittable {
                app.buttons["取消"].tap()
            }
        }

        assertStillRunning(app, "CSV 数据导出")
    }

    // MARK: - 3. 设置 → 备份数据（JSON）

    /// 覆盖 P0-2：设置页「备份数据」触发 JSON 导出。
    /// 原实现 `record.habit.id` 对孤儿记录强解包会 EXC_BAD_ACCESS。
    @MainActor
    func testBackupJSONFromSettings_DoesNotCrash() throws {
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "App 应正常启动")

        switchTab(app, tabName: "设置")

        let backupButton = scrollToButton(app, identifier: "backupJSONButton")
        XCTAssertTrue(backupButton.waitForExistence(timeout: 5),
                      "设置页应存在「备份数据」入口（已滚动查找）")

        backupButton.tap()
        Thread.sleep(forTimeInterval: 2.5)

        let shareSheet = app.otherElements["ActivityListView"]
        if shareSheet.exists {
            // 竞态修复（2026-11-19）：分享面板动画期间 exists 可能先为 true、随后元素重建，
            // 直接 tap 会抛 "No matches found"。等面板稳定 + isHittable 双重判据。
            Thread.sleep(forTimeInterval: 1.0)
            let closeButton = app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] %@", "关闭")
            ).firstMatch
            if closeButton.exists && closeButton.isHittable {
                closeButton.tap()
            } else if app.buttons["取消"].exists && app.buttons["取消"].isHittable {
                app.buttons["取消"].tap()
            }
        }

        assertStillRunning(app, "JSON 数据备份")
    }

    // MARK: - 4. 习惯删除链路（显式级联删除）

    /// 覆盖 P0-3 根因修复：删除习惯时显式级联删除其打卡记录。
    /// 验证删除操作后 UI 正常刷新、App 不崩溃。
    @MainActor
    func testDeleteHabitFromHabitTab_DoesNotCrash() throws {
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "App 应正常启动")

        switchTab(app, tabName: "习惯")

        // 等待习惯页加载
        Thread.sleep(forTimeInterval: 1.5)
        assertStillRunning(app, "习惯页加载")

        // 找到第一个习惯行并左滑删除
        // 注：模拟器可能无预置习惯数据，此时滚动查找习惯卡片；
        // 找到任意可滑动元素即验证删除链路不崩溃。
        var target: XCUIElement?
        for _ in 0..<5 {
            let cells = app.cells
            if cells.count > 0 {
                target = cells.element(boundBy: 0)
                break
            }
            let buttons = app.buttons
            if buttons.count > 0 {
                target = buttons.element(boundBy: 0)
                break
            }
            app.swipeUp()
            Thread.sleep(forTimeInterval: 0.4)
        }

        guard let element = target else {
            throw XCTSkip("习惯页无可操作元素（无预置数据），跳过删除测试")
        }

        element.swipeLeft()
        Thread.sleep(forTimeInterval: 0.8)

        let deleteButton = app.buttons["删除"]
        if deleteButton.exists {
            deleteButton.tap()
        }

        assertStillRunning(app, "习惯删除（含级联删除打卡记录）")
    }

    // MARK: - 5. 设置 → 恢复数据（确认弹窗链路）

    /// 覆盖 P1-4 相关 UI 链路：恢复入口的确认弹窗。
    /// 仅验证 UI 可达且不崩溃，不实际恢复（文件选择器需交互）。
    @MainActor
    func testRestoreDataEntry_DoesNotCrash() throws {
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "App 应正常启动")

        switchTab(app, tabName: "设置")

        let restoreButton = scrollToButton(app, identifier: "restoreDataButton")
        XCTAssertTrue(restoreButton.waitForExistence(timeout: 5),
                      "设置页应存在「恢复数据」入口（已滚动查找）")

        restoreButton.tap()
        Thread.sleep(forTimeInterval: 1.2)

        // 应弹出恢复确认弹窗
        let confirmButton = app.buttons["恢复数据"].firstMatch
        if confirmButton.exists {
            // 取消，避免进入文件选择器
            let cancel = app.buttons["取消"]
            if cancel.exists { cancel.tap() }
        }

        assertStillRunning(app, "恢复数据入口")
    }

    // MARK: - 无障碍：大字体下的布局回归（2026-10-15）

    /// AX 最大字体档下，专注页关键元素不得被压扁/截断。
    ///
    /// 缺陷背景：AX5 下「自定义」chip 侧有 `maxWidth: 140` 硬上限，实测被压到 85pt
    /// （「图标+自定义」需约 110pt）→ 显示成「自定义…」；同行「关联任务」更被压到
    /// 只剩图标、文字完全消失。修复：两者改 VStack 纵向堆叠 + 去掉文案自带省略号 +
    /// 文本加 minimumScaleFactor 兜底。
    ///
    /// 断言判据（实测基线，AX5 = accessibility-extra-extra-extra-large）：
    /// - 元素 frame 宽度 ≥ 阈值（被压扁则远小于此）
    /// - 静态文本 frame 高度 ≥ 40pt（文字被压没时高度塌陷）
    /// - 无障碍 label 完整可读（不含被截断的省略号）
    /// - isHittable == true（未被其它元素遮挡）
    ///
    /// 运行前置：`xcrun simctl ui <UDID> content_size accessibility-extra-extra-extra-large`
    /// 自包含（2026-11-19）：不再依赖外部前置 —— 通过启动参数把本 App 的 Dynamic Type
    /// 强制为 AX XXXL，避免"忘设字号 → chip 天然 85pt → 假红"。
    @MainActor
    func testAccessibility_AXMaxFont_FocusPageElementsNotSquashed() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        Thread.sleep(forTimeInterval: 3)

        if app.tabBars.buttons["专注"].exists {
            app.tabBars.buttons["专注"].tap()
            Thread.sleep(forTimeInterval: 2)
        }

        // 「自定义」时长 chip：不得被压到 140pt 以下（修复前实测 85pt）
        let customChip = app.buttons["自定义"]
        XCTAssertTrue(customChip.waitForExistence(timeout: 5), "应存在「自定义」时长按钮")
        XCTAssertGreaterThanOrEqual(customChip.frame.width, 160,
                                    "「自定义」chip 被压扁（width=\(customChip.frame.width)pt，修复前 AX5 下为 85pt）")
        XCTAssertTrue(customChip.isHittable, "「自定义」chip 应可点击")

        // 「关联任务」卡片：修复前在 AX5 下文字被完全压没（只剩图标）
        let taskBinding = app.buttons["关联任务"]
        XCTAssertTrue(taskBinding.waitForExistence(timeout: 5), "应存在「关联任务」按钮")
        XCTAssertGreaterThanOrEqual(taskBinding.frame.width, 200,
                                     "「关联任务」卡片被压扁（width=\(taskBinding.frame.width)pt）")
        XCTAssertTrue(taskBinding.isHittable, "「关联任务」卡片应可点击")

        // 静态文本高度：被压没时高度塌陷到接近 0
        for label in ["自定义", "关联任务"] {
            let text = app.staticTexts[label]
            XCTAssertTrue(text.waitForExistence(timeout: 3), "应存在文本「\(label)」")
            XCTAssertGreaterThanOrEqual(text.frame.height, 40,
                                        "文本「\(label)」高度塌陷（height=\(text.frame.height)pt，疑似被压没）")
        }

        // 无障碍 label 完整：不应是被截断的「自定义…」
        XCTAssertEqual(customChip.label, "自定义",
                       "chip 的无障碍 label 不应含截断省略号（实际「\(customChip.label)」）")

        // 开始按钮在 AX5 下仍应保持可点击的主体尺寸
        let startButton = app.buttons["开始"]
        if startButton.exists {
            XCTAssertGreaterThanOrEqual(startButton.frame.width, 44,
                                        "开始按钮被压到小于最小触控目标")
        }
    }
}
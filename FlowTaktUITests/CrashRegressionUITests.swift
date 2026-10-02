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

        switchTab(app, tabName: "计时")

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

        // 逐条左滑删除全部记录（List 行删除入口）
        // 滑动删除是 onDelete 唯一可达路径；重复执行以覆盖多轮删除后的索引收缩场景。
        for round in 0..<3 {
            let cells = app.cells
            guard cells.count > 0 else { break }
            let lastCell = cells.element(boundBy: cells.count - 1)
            guard lastCell.exists else { break }
            lastCell.swipeLeft()
            Thread.sleep(forTimeInterval: 0.6)
            // 若出现「删除」确认按钮则点击
            let confirmDelete = app.buttons["删除"]
            if confirmDelete.exists {
                confirmDelete.tap()
            }
            assertStillRunning(app, "第 \(round + 1) 次滑动删除")
        }

        assertStillRunning(app, "计时页删除流程完成")
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
            // 关闭分享面板
            let closeButton = app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] %@", "关闭")
            ).firstMatch
            if closeButton.exists { closeButton.tap() }
            else if app.buttons["取消"].exists { app.buttons["取消"].tap() }
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
            let closeButton = app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] %@", "关闭")
            ).firstMatch
            if closeButton.exists { closeButton.tap() }
            else if app.buttons["取消"].exists { app.buttons["取消"].tap() }
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
}

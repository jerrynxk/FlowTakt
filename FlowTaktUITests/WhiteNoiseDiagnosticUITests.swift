import XCTest

/// 白噪音链路验证：开关 + 环境音抽屉选择后 UI 状态正确。
///
/// 2026-11-02 重写：旧用例针对 v1.3 的「分段选择器平铺四种音效」，
/// 而当前 UI 已改为「卡片 + Toggle + 底部抽屉选音效」——
/// 分段按钮不复存在，用例从那时起就一直失败（测试未随改版更新）。
/// 现按当前结构重写：开启开关 → 点选择行弹出抽屉 → 选音效 → 校验选择行文案已更新。
///
/// 2026-11-22 适配页面简化：白噪音卡收进专注页工具条的 sheet，
/// 需先点「白噪音」按钮打开 sheet，再操作其中的 toggle。
final class WhiteNoiseDiagnosticUITests: XCTestCase {

    @MainActor
    func testWhiteNoiseToggleAndTypeSwitch() throws {
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        app.launch()

        // 0. 先点专注页工具条的白噪音按钮，打开设置 sheet
        let toolbarButton = app.buttons["toolbarWhiteNoiseButton"]
        XCTAssertTrue(toolbarButton.waitForExistence(timeout: 5), "应存在工具条白噪音按钮")
        toolbarButton.tap()
        Thread.sleep(forTimeInterval: 0.5)

        // 1. 白噪音开关（SwiftUI Toggle，a11y identifier "whiteNoiseToggle"，位于 sheet 内）
        let toggle = app.switches["whiteNoiseToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "sheet 内应存在白噪音开关")

        // 2. 选择行仅在开关开启时可点，先确保为开
        if (toggle.value as? String) == "0" {
            toggle.tap()
            Thread.sleep(forTimeInterval: 0.6)
        }

        // 3. 点选择行，弹出环境音抽屉
        //    选择行 label 形如「白噪音类型：白噪音」，选中变化时后缀会跟着变
        let selector = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "白噪音类型"))
            .firstMatch
        XCTAssertTrue(selector.waitForExistence(timeout: 3), "应存在环境音选择行")
        XCTAssertTrue(selector.isHittable, "开关开启后环境音选择行应可点")
        selector.tap()

        // 4. 抽屉内选择「雨声」
        let rain = app.buttons["雨声"]
        XCTAssertTrue(rain.waitForExistence(timeout: 4), "环境音库应含「雨声」")
        rain.tap()
        Thread.sleep(forTimeInterval: 1.0)

        // 5. 选择后抽屉自动收起，选择行文案应已更新为「雨声」
        let updated = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", "雨声"))
            .firstMatch
        XCTAssertTrue(updated.waitForExistence(timeout: 3), "选择后选择行应显示「雨声」")

        // 6. 关闭开关后仍可访问
        toggle.tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 3), "关闭后开关仍应可访问")
    }
}

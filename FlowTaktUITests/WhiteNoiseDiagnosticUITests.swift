import XCTest

/// 白噪音链路验证：开关翻转 + 类型分段选择器切换后 UI 状态正确。
final class WhiteNoiseDiagnosticUITests: XCTestCase {

    @MainActor
    func testWhiteNoiseToggleAndTypeSwitch() throws {
        let app = XCUIApplication()
        // 重置为竖屏
        XCUIDevice.shared.orientation = .portrait

        app.launch()

        // 1. v1.3 改版：开关变为 SwiftUI Toggle（a11y identifier "whiteNoiseToggle"）
        let toggle = app.switches["whiteNoiseToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "应存在白噪音开关")

        // 2. 依次点击分段选择器的三种真实环境音类型（segmented 段以文本按钮暴露）
        for name in ["雨声", "溪流", "咖啡厅", "白噪音"] {
            let segment = app.buttons[name]
            XCTAssertTrue(segment.waitForExistence(timeout: 3), "类型选择器应含「\(name)」")
            segment.tap()
            Thread.sleep(forTimeInterval: 2)
        }

        // 3. 关闭白噪音
        toggle.tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 3), "关闭后开关仍应可访问")
    }
}

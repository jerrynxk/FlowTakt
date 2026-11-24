import XCTest

/// 阶段 A UI 冒烟：任务排序、日程周视图、统计年热力图入口。
final class PhaseAUITests: XCTestCase {

    @MainActor
    func testPhaseAFeaturesSmoke() throws {
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

        // 等待 TabBar 出现（冷启动首帧可能延迟，避免直接 tap 竞态失败）
        let tabBarAppeared = app.tabBars.firstMatch.waitForExistence(timeout: 10)
        if !tabBarAppeared {
            try? XCUIScreen.main.screenshot().pngRepresentation
                .write(to: URL(fileURLWithPath: "/tmp/ui-fail-\(name).png"))
        }
        XCTAssertTrue(tabBarAppeared, "App 应完成启动并显示 TabBar")

        // 1. 计划 tab（默认任务页）：排序入口存在
        app.tabBars.buttons["计划"].tap()
        // 无障碍补齐（2026-11-02）：排序入口的 label 已扩展为「排序：<当前排序方式>」，
        // 精确文案匹配会随排序状态变化 → 改按 accessibilityIdentifier 查询
        let sortButton = app.descendants(matching: .any)["sortMenu"]
        XCTAssertTrue(sortButton.waitForExistence(timeout: 4), "任务页应有排序入口")

        // 2. 计划内切到「日程」→ 周视图切换存在并可用
        app.buttons["日程"].tap()
        let weekSegment = app.buttons["周视图"]
        XCTAssertTrue(weekSegment.waitForExistence(timeout: 4), "日程页应有周视图切换")
        weekSegment.tap()
        Thread.sleep(forTimeInterval: 1)

        // 3. 统计 tab：年热力图存在
        app.tabBars.buttons["统计"].tap()
        // 修复（2026-10-14 审查 T3）：改按 accessibilityIdentifier 查询（原先按中文 label
        // 精确匹配，依赖 combine 容器的隐式暴露行为）。descendants(.any) 兼容容器元素类型不确定。
        let heatmap = app.descendants(matching: .any)["yearHeatmap"]
        XCTAssertTrue(heatmap.waitForExistence(timeout: 4), "统计页应有专注年热力图")
    }
}

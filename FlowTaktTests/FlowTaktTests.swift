//
//  FlowTaktTests.swift
//  FlowTaktTests
//
//  Created by 牛星 on 2026/6/9.
//

import XCTest
@testable import FlowTakt

/// AppConstants 基础测试（替换原 Xcode 默认模板）
final class FlowTaktTests: XCTestCase {

    func testAppConstants_defaultDurationsArePositive() {
        XCTAssertGreaterThan(AppConstants.defaultFocusDuration, 0)
        XCTAssertGreaterThan(AppConstants.defaultShortBreakDuration, 0)
        XCTAssertGreaterThan(AppConstants.defaultLongBreakDuration, 0)
    }

    func testAppConstants_longBreakAfterRoundsIsPositive() {
        XCTAssertGreaterThan(AppConstants.longBreakAfterRounds, 0)
    }

    func testAppConstants_pointsPerCompletedPomodoroIsPositive() {
        XCTAssertGreaterThan(AppConstants.pointsPerCompletedPomodoro, 0)
    }

    func testAppConstants_pointsPenaltyIsNegative() {
        // 惩罚积分应为负数（业务语义校验）
        XCTAssertLessThan(AppConstants.pointsPenaltyPerInterrupt, 0)
    }

    func testAppConstants_achievementsAreNotEmpty() {
        XCTAssertFalse(AppConstants.achievements.isEmpty)
        // 验证标识符唯一
        let identifiers = AppConstants.achievements.map(\.identifier)
        XCTAssertEqual(identifiers.count, Set(identifiers).count, "成就标识符必须唯一")
    }

    func testAppConstants_cloudKitContainerIdentifier() {
        XCTAssertEqual(AppConstants.cloudKitContainerIdentifier, "iCloud.com.flowtakt")
    }

    // MARK: - 深链路由（P2.6 Widget 深链到具体事件）

    @MainActor
    func testHandleDeepLink_scheduleWithID_routesToPlanCalendarAndPendingItem() {
        let app = AppDependency()
        let id = UUID().uuidString
        app.handleDeepLink(URL(string: "flowtakt://schedule/\(id)")!)

        XCTAssertEqual(app.selectedMainTab, MainTab.plan)
        XCTAssertEqual(app.pendingPlanTab, PlanView.PlanTab.calendar)
        XCTAssertEqual(app.pendingScheduleItemID, id)
    }

    @MainActor
    func testHandleDeepLink_tasksArchived_routesToPlanTaskArchived() {
        let app = AppDependency()
        app.handleDeepLink(URL(string: "flowtakt://tasks/archived")!)

        XCTAssertEqual(app.selectedMainTab, MainTab.plan)
        XCTAssertEqual(app.pendingPlanTab, PlanView.PlanTab.task)
        XCTAssertEqual(app.pendingTaskTab, "archived")
    }

    @MainActor
    func testHandleDeepLink_settingsTab_routesToSettings() {
        let app = AppDependency()
        app.handleDeepLink(URL(string: "flowtakt://settings")!)

        XCTAssertEqual(app.selectedMainTab, MainTab.settings)
    }

    @MainActor
    func testHandleDeepLink_unknownScheme_isIgnored() {
        let app = AppDependency()
        app.handleDeepLink(URL(string: "https://example.com")!)

        // 未知 scheme 不应改变默认 tab
        XCTAssertEqual(app.selectedMainTab, MainTab.focus)
    }

    // ========================================================================
    // MARK: - TimeInterval.formattedDuration（审查修复 P2 #28）
    // ========================================================================

    func testFormattedDuration_UnderOneMinute_ShowsOneMinute() {
        // 审查修复：<60 秒不再显示"0分钟"
        let d: TimeInterval = 30
        let text = d.formattedDuration
        XCTAssertFalse(text.contains("0"), "非零但不足 1 分钟不应显示 0 分钟，实际: \(text)")
    }

    func testFormattedDuration_Zero_ShowsZero() {
        let text = TimeInterval(0).formattedDuration
        XCTAssertTrue(text.contains("0"), "零时长应显示 0 分钟")
    }

    func testFormattedDuration_OneHour_ShowsHour() {
        let text = TimeInterval(3600).formattedDuration
        XCTAssertFalse(text.isEmpty)
    }
}

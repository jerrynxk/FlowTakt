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
}

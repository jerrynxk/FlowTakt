import XCTest
@testable import FlowTakt

// MARK: - L10nTests
// 测试本地化系统：中英文切换、所有关键字符串的主语言覆盖

final class L10nTests: XCTestCase {
    let english = "en"
    let chinese = "zh-Hans"

    override func tearDown() {
        L10n.shared.appLanguage = chinese
        super.tearDown()
    }

    // ========================================================================
    // MARK: - 语言切换
    // ========================================================================

    func testDefaultLanguage_IsChinese() {
        L10n.shared.appLanguage = chinese
        XCTAssertEqual(L10n.shared.appLanguage, chinese)
        XCTAssertFalse(L10n.shared.isEnglish)
        XCTAssertFalse(L10n.isEnglish)
    }

    func testSwitchToEnglish_ThenIsEnglishIsTrue() {
        L10n.shared.appLanguage = english
        XCTAssertTrue(L10n.shared.isEnglish)
        XCTAssertTrue(L10n.isEnglish)
    }

    func testSwitchBackToChinese_ThenChineseStringsReturned() {
        L10n.shared.appLanguage = english
        L10n.shared.appLanguage = chinese

        XCTAssertEqual(L10n.shared.focus, "专注")
        XCTAssertEqual(L10n.shared.plan, "计划")
    }

    // ========================================================================
    // MARK: - Tab 标签
    // ========================================================================

    func testTabLabels_Chinese() {
        L10n.shared.appLanguage = chinese
        XCTAssertEqual(L10n.shared.focus, "专注")
        XCTAssertEqual(L10n.shared.plan, "计划")
        XCTAssertEqual(L10n.shared.stats, "统计")
        XCTAssertEqual(L10n.shared.habits, "习惯")
        XCTAssertEqual(L10n.shared.settings, "设置")
    }

    func testTabLabels_English() {
        L10n.shared.appLanguage = english
        XCTAssertEqual(L10n.shared.focus, "Focus")
        XCTAssertEqual(L10n.shared.plan, "Plan")
        XCTAssertEqual(L10n.shared.stats, "Stats")
        XCTAssertEqual(L10n.shared.habits, "Habits")
        XCTAssertEqual(L10n.shared.settings, "Settings")
    }

    // ========================================================================
    // MARK: - 通用文本
    // ========================================================================

    func testCommonTexts_Chinese() {
        L10n.shared.appLanguage = chinese
        XCTAssertEqual(L10n.shared.保存, "保存")
        XCTAssertEqual(L10n.shared.取消, "取消")
        XCTAssertEqual(L10n.shared.删除, "删除")
        XCTAssertEqual(L10n.shared.确定, "确定")
        XCTAssertEqual(L10n.shared.完成, "完成")
    }

    func testCommonTexts_English() {
        L10n.shared.appLanguage = english
        XCTAssertEqual(L10n.shared.保存, "Save")
        XCTAssertEqual(L10n.shared.取消, "Cancel")
        XCTAssertEqual(L10n.shared.删除, "Delete")
    }

    // ========================================================================
    // MARK: - 插值字符串
    // ========================================================================

    func testRound_Chinese() {
        L10n.shared.appLanguage = chinese
        XCTAssertEqual(L10n.shared.round(3), "第 3 轮")
    }

    func testRound_English() {
        L10n.shared.appLanguage = english
        XCTAssertEqual(L10n.shared.round(3), "Round 3")
    }

    func testTodayCompleted_Chinese() {
        L10n.shared.appLanguage = chinese
        XCTAssertEqual(L10n.shared.todayCompleted(5), "今天已完成 5 个番茄钟")
    }

    func testTodayCompleted_English() {
        L10n.shared.appLanguage = english
        XCTAssertEqual(L10n.shared.todayCompleted(5), "Today completed 5 pomodoros")
    }

    func testEstimatedPomodoros_Chinese() {
        L10n.shared.appLanguage = chinese
        XCTAssertEqual(L10n.shared.estimatedPomodoros(3), "3 个番茄钟")
    }

    // ========================================================================
    // MARK: - 成就本地化
    // ========================================================================

    func testAchievementTitle_Chinese() {
        L10n.shared.appLanguage = chinese
        XCTAssertEqual(L10n.shared.achievementTitle("first_pomodoro"), "初次专注")
        XCTAssertEqual(L10n.shared.achievementTitle("pomodoros_10"), "专注新手")
        XCTAssertEqual(L10n.shared.achievementTitle("pomodoros_100"), "专注大师")
        XCTAssertEqual(L10n.shared.achievementTitle("streak_7"), "一周坚持")
        XCTAssertEqual(L10n.shared.achievementTitle("points_100"), "积分新星")
    }

    func testAchievementTitle_English() {
        L10n.shared.appLanguage = english
        XCTAssertEqual(L10n.shared.achievementTitle("first_pomodoro"), "First Pomodoro")
        XCTAssertEqual(L10n.shared.achievementTitle("pomodoros_100"), "Focus Master")
        XCTAssertEqual(L10n.shared.achievementTitle("streak_7"), "Weekly Streak")
    }

    func testAchievementTitle_UnknownIdentifier_ReturnsIdentifier() {
        L10n.shared.appLanguage = chinese
        XCTAssertEqual(L10n.shared.achievementTitle("unknown_xyz"), "unknown_xyz")
    }

    func testAchievementDesc_Chinese() {
        L10n.shared.appLanguage = chinese
        XCTAssertEqual(L10n.shared.achievementDesc("first_pomodoro", threshold: 1), "完成你的第一个番茄钟")
    }

    func testAchievementDesc_English() {
        L10n.shared.appLanguage = english
        XCTAssertEqual(L10n.shared.achievementDesc("first_pomodoro", threshold: 1), "Complete your first pomodoro")
    }

    func testAchievementCategory_Chinese() {
        L10n.shared.appLanguage = chinese
        XCTAssertEqual(L10n.shared.achievementCategory("total"), "累积成就")
        XCTAssertEqual(L10n.shared.achievementCategory("streak"), "连续成就")
    }

    // ========================================================================
    // MARK: - 番茄钟状态
    // ========================================================================

    func testPomodoroComplete_Suffix() {
        L10n.shared.appLanguage = chinese
        let result = L10n.shared.番茄钟已完成("测试任务")
        XCTAssertTrue(result.contains("测试任务"))
    }

    // ========================================================================
    // MARK: - 时长格式化
    // ========================================================================

    func testHoursMinutes_Chinese() {
        L10n.shared.appLanguage = chinese
        XCTAssertEqual(L10n.shared.小时分钟(2, 30), "2小时30分钟")
    }

    func testHoursMinutes_English() {
        L10n.shared.appLanguage = english
        XCTAssertEqual(L10n.shared.小时分钟(2, 30), "2h 30m")
    }

    func testMinutesOnly_Chinese() {
        L10n.shared.appLanguage = chinese
        XCTAssertEqual(L10n.shared.分钟(45), "45分钟")
    }

    func testMinutesOnly_English() {
        L10n.shared.appLanguage = english
        XCTAssertEqual(L10n.shared.分钟(45), "45m")
    }

    // ========================================================================
    // MARK: - 每日提醒
    // ========================================================================

    func testDailyReminderTitle_Chinese() {
        L10n.shared.appLanguage = chinese
        XCTAssertEqual(L10n.shared.每日提醒标题, "今天别忘了专注哦！")
    }

    func testDailyReminderTitle_English() {
        L10n.shared.appLanguage = english
        XCTAssertEqual(L10n.shared.每日提醒标题, "Don't forget to focus today!")
    }

    // ========================================================================
    // MARK: - 使用说明
    // ========================================================================

    func testGuideContent_ForAllModules_ReturnsNonEmpty() {
        L10n.shared.appLanguage = chinese
        let modules = ["focus", "task", "calendar", "habit", "timer", "stats", "achievement"]
        for module in modules {
            let content = L10n.shared.guideContent(for: module)
            XCTAssertFalse(content.isEmpty, "模块 '\(module)' 的使用说明不应为空")
        }
    }

    func testGuideContent_UnknownModule_ReturnsEmpty() {
        L10n.shared.appLanguage = chinese
        XCTAssertEqual(L10n.shared.guideContent(for: "nonexistent"), "")
    }

    // ========================================================================
    // MARK: - 边界条件
    // ========================================================================

    func testRound_Zero() {
        L10n.shared.appLanguage = chinese
        XCTAssertTrue(L10n.shared.round(0).contains("0"))
    }

    func testDeleteConfirm_ContainsTitleInBothLanguages() {
        L10n.shared.appLanguage = chinese
        let chineseConfirm = L10n.shared.deleteConfirm("我的任务")
        XCTAssertTrue(chineseConfirm.contains("我的任务"))

        L10n.shared.appLanguage = english
        let englishConfirm = L10n.shared.deleteConfirm("My Task")
        XCTAssertTrue(englishConfirm.contains("My Task"))
    }

    func testPomodoroTips_HaveFiveTips() {
        L10n.shared.appLanguage = chinese
        XCTAssertEqual(L10n.shared.pomodoroTips.count, 5)

        L10n.shared.appLanguage = english
        XCTAssertEqual(L10n.shared.pomodoroTips.count, 5)
    }

    func testHabitFrequencyTexts() {
        L10n.shared.appLanguage = chinese
        XCTAssertEqual(L10n.shared.每天, "每天")
        XCTAssertEqual(L10n.shared.每周, "每周")
        XCTAssertEqual(L10n.shared.每月, "每月")

        L10n.shared.appLanguage = english
        XCTAssertEqual(L10n.shared.每天, "Daily")
        XCTAssertEqual(L10n.shared.每周, "Weekly")
        XCTAssertEqual(L10n.shared.每月, "Monthly")
    }

    func testNotificationStatusTexts() {
        L10n.shared.appLanguage = chinese
        XCTAssertEqual(L10n.shared.通知已授权, "已授权")
        XCTAssertEqual(L10n.shared.通知未授权, "未授权")
    }
}

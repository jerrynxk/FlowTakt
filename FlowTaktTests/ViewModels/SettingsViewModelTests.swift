import XCTest
import Combine
import SwiftUI
@testable import FlowTakt

// MARK: - SettingsViewModelTests
// 测试 SettingsViewModel：各项设置读/写、默认值、重置、语言切换、同步触发

final class SettingsViewModelTests: XCTestCase {
    var mockSyncService: MockSettingsSyncService!
    var viewModel: SettingsViewModel!
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        // 清除 UserDefaults 避免跨测试污染
        let domain = Bundle.main.bundleIdentifier ?? ""
        UserDefaults.standard.removePersistentDomain(forName: domain)
        // 单独清理常用 key
        let keys = ["focusDuration", "shortBreakDuration", "longBreakDuration",
                    "longBreakAfterRounds", "soundEnabled", "vibrationEnabled",
                    "dailyReminderEnabled", "iCloudSyncEnabled", "autoStartBreaks",
                    "autoStartFocus", "appLanguage", "reminderHour", "reminderMinute",
                    "weeklyReportEnabled", "colorSchemeOption", "speechEnabled"]
        for key in keys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        mockSyncService = MockSettingsSyncService()
        viewModel = SettingsViewModel(syncService: mockSyncService)
        cancellables = Set<AnyCancellable>()
    }

    override func tearDown() {
        viewModel = nil
        mockSyncService = nil
        cancellables = nil
        super.tearDown()
    }

    // ========================================================================
    // MARK: - 初始默认值
    // ========================================================================

    func testInitialValues_MatchAppConstants() {
        XCTAssertEqual(viewModel.focusDuration, AppConstants.defaultFocusDuration)
        XCTAssertEqual(viewModel.shortBreakDuration, AppConstants.defaultShortBreakDuration)
        XCTAssertEqual(viewModel.longBreakDuration, AppConstants.defaultLongBreakDuration)
        XCTAssertEqual(viewModel.longBreakAfterRounds, AppConstants.longBreakAfterRounds)
        XCTAssertTrue(viewModel.soundEnabled)
        XCTAssertTrue(viewModel.vibrationEnabled)
        XCTAssertFalse(viewModel.dailyReminderEnabled)
        XCTAssertTrue(viewModel.autoStartBreaks)
        XCTAssertFalse(viewModel.autoStartFocus)
    }

    func testLanguageOptions_AreCorrect() {
        XCTAssertEqual(viewModel.languageOptions.count, 2)
        XCTAssertEqual(viewModel.languageOptions[0], "zh-Hans")
        XCTAssertEqual(viewModel.languageOptions[1], "en")
    }

    func testDurationOptions_AreCorrect() {
        XCTAssertEqual(viewModel.focusOptions.count, 5)
        XCTAssertEqual(viewModel.shortBreakOptions.count, 3)
        XCTAssertEqual(viewModel.longBreakOptions.count, 4)
    }

    // ========================================================================
    // MARK: - 设置变更
    // ========================================================================

    func testUpdateFocusDuration_GivenValidIndex_ThenUpdatesDuration() {
        // When: 选择 45 分钟 (index 3)
        viewModel.updateFocusDuration(at: 3)

        // Then
        XCTAssertEqual(viewModel.selectedFocusOption, 3)
        XCTAssertEqual(viewModel.focusDuration, AppConstants.focusDurationOptions[3])
    }

    func testUpdateFocusDuration_GivenInvalidIndex_ThenNoChange() {
        let original = viewModel.focusDuration

        // When
        viewModel.updateFocusDuration(at: 100)

        // Then
        XCTAssertEqual(viewModel.focusDuration, original)
    }

    func testUpdateShortBreakDuration_WhenChanged_ThenReflectsNewValue() {
        viewModel.updateShortBreakDuration(at: 2) // 10 分钟
        XCTAssertEqual(viewModel.shortBreakDuration, AppConstants.shortBreakOptions[2])
    }

    func testUpdateLongBreakDuration_WhenChanged_ThenReflectsNewValue() {
        viewModel.updateLongBreakDuration(at: 3) // 30 分钟
        XCTAssertEqual(viewModel.longBreakDuration, AppConstants.longBreakOptions[3])
    }

    // ========================================================================
    // MARK: - 语言切换
    // ========================================================================

    func testUpdateLanguage_ToEnglish_ThenChangesAppLanguage() {
        // When
        viewModel.updateLanguage(at: 1) // English

        // Then
        XCTAssertEqual(viewModel.appLanguage, "en")
        XCTAssertEqual(viewModel.selectedLanguageOption, 1)
        XCTAssertEqual(L10n.shared.appLanguage, "en")
    }

    func testUpdateLanguage_BackToChinese_ThenRestoresChinese() {
        viewModel.updateLanguage(at: 1) // en
        viewModel.updateLanguage(at: 0) // zh-Hans

        XCTAssertEqual(viewModel.appLanguage, "zh-Hans")
        XCTAssertEqual(L10n.shared.appLanguage, "zh-Hans")
    }

    // ========================================================================
    // MARK: - 重置为默认值
    // ========================================================================

    func testResetToDefaults_ThenAllSettingsRevert() {
        // Given: 先修改所有值
        viewModel.updateFocusDuration(at: 4)         // 60 min
        viewModel.updateShortBreakDuration(at: 2)    // 修改短休
        viewModel.updateLongBreakDuration(at: 3)     // 修改长休
        viewModel.updateLanguage(at: 1)              // English
        viewModel.soundEnabled = false
        viewModel.vibrationEnabled = false
        viewModel.speechEnabled = false
        viewModel.weeklyReportEnabled = false
        viewModel.autoStartFocus = true
        viewModel.autoStartBreaks = false
        viewModel.iCloudSyncEnabled = true
        viewModel.dailyReminderEnabled = true
        viewModel.colorSchemeOption = "dark"
        viewModel.dailyReminderTime = DateComponents(hour: 18, minute: 30)

        // When
        viewModel.resetToDefaults()

        // Then - 全部键回到默认值
        XCTAssertEqual(viewModel.focusDuration, AppConstants.defaultFocusDuration)
        XCTAssertEqual(viewModel.shortBreakDuration, AppConstants.defaultShortBreakDuration)
        XCTAssertEqual(viewModel.longBreakDuration, AppConstants.defaultLongBreakDuration)
        XCTAssertEqual(viewModel.longBreakAfterRounds, AppConstants.longBreakAfterRounds)
        XCTAssertTrue(viewModel.soundEnabled)
        XCTAssertTrue(viewModel.vibrationEnabled)
        XCTAssertTrue(viewModel.speechEnabled, "speechEnabled 应重置为默认 true")
        XCTAssertTrue(viewModel.weeklyReportEnabled, "weeklyReportEnabled 应重置为默认 true")
        XCTAssertTrue(viewModel.autoStartBreaks)
        XCTAssertFalse(viewModel.autoStartFocus)
        XCTAssertFalse(viewModel.dailyReminderEnabled)
        XCTAssertFalse(viewModel.iCloudSyncEnabled)
        XCTAssertEqual(viewModel.appLanguage, "zh-Hans", "语言应重置为默认中文")
        XCTAssertEqual(L10n.shared.appLanguage, "zh-Hans")
        XCTAssertEqual(viewModel.colorSchemeOption, "system")
        XCTAssertEqual(viewModel.dailyReminderTime.hour, 9)
        XCTAssertEqual(viewModel.dailyReminderTime.minute, 0)
    }

    func testResetToDefaults_ThenSelectionIndicesStayInSync() {
        // Given - 修改时长与语言
        viewModel.updateFocusDuration(at: 4) // 60 min
        viewModel.updateLanguage(at: 1)      // English
        XCTAssertEqual(viewModel.selectedFocusOption, 4)
        XCTAssertEqual(viewModel.selectedLanguageOption, 1)

        // When
        viewModel.resetToDefaults()

        // Then - 选择器索引与存储值重新同步（UI 显示与实际设置一致）
        XCTAssertEqual(viewModel.selectedFocusOption,
                       viewModel.focusOptions.firstIndex(of: viewModel.focusDuration))
        XCTAssertEqual(viewModel.selectedShortBreakOption,
                       viewModel.shortBreakOptions.firstIndex(of: viewModel.shortBreakDuration))
        XCTAssertEqual(viewModel.selectedLongBreakOption,
                       viewModel.longBreakOptions.firstIndex(of: viewModel.longBreakDuration))
        XCTAssertEqual(viewModel.selectedLanguageOption, 0, "重置后语言索引应回到 zh-Hans")
    }

    func testUpdateFocusDuration_NegativeIndex_ThenIgnored() {
        // Given
        let original = viewModel.focusDuration

        // When - 负索引（防御越界）
        viewModel.updateFocusDuration(at: -1)

        // Then - 值不变，不崩溃
        XCTAssertEqual(viewModel.focusDuration, original)
    }

    func testUpdateLanguage_OutOfRangeIndex_ThenIgnored() {
        // Given
        let original = viewModel.appLanguage

        // When - 越界索引
        viewModel.updateLanguage(at: 99)

        // Then - 值不变，不崩溃
        XCTAssertEqual(viewModel.appLanguage, original)
    }

    // ========================================================================
    // MARK: - iCloud 同步
    // ========================================================================

    func testICloudSyncEnabled_WhenSetTrue_ThenCallsForceSync() {
        // When
        viewModel.iCloudSyncEnabled = true

        // Then
        XCTAssertTrue(mockSyncService.forceSyncCalled)
    }

    func testForceSync_ManuallyTriggered_ThenCallsSyncService() {
        // When
        viewModel.forceSync()

        // Then
        XCTAssertTrue(mockSyncService.forceSyncCalled)
    }

    // ========================================================================
    // MARK: - 数据库重置回调
    // ========================================================================

    func testResetDatabase_WhenCallbackNotSet_ThenCallsCompletionWithFalse() {
        // Given
        let expectation = expectation(description: "无回调时 completion(false)")

        // When
        viewModel.resetDatabase { success in
            XCTAssertFalse(success)
            expectation.fulfill()
        }

        // Then
        wait(for: [expectation], timeout: 1)
    }

    func testResetDatabase_WhenCallbackSucceeds_ThenCallsCompletionWithTrue() {
        // Given
        viewModel.onResetDatabase = { completion in completion(true) }
        let expectation = expectation(description: "回调成功时 completion(true)")

        // When
        viewModel.resetDatabase { success in
            XCTAssertTrue(success)
            expectation.fulfill()
        }

        // Then
        wait(for: [expectation], timeout: 1)
    }

    func testResetDatabase_WhenCallbackFails_ThenCallsCompletionWithFalse() {
        // Given
        viewModel.onResetDatabase = { completion in completion(false) }
        let expectation = expectation(description: "回调失败时 completion(false)")

        // When
        viewModel.resetDatabase { success in
            XCTAssertFalse(success)
            expectation.fulfill()
        }

        // Then
        wait(for: [expectation], timeout: 1)
    }

    // ========================================================================
    // MARK: - Published 属性发布
    // ========================================================================

    func testPublishedFocusDuration_WhenUpdated_ThenPublishesNewValue() {
        var emissionCount = 0
        let cancellable = viewModel.objectWillChange
            .sink { emissionCount += 1 }

        viewModel.updateFocusDuration(at: 2)

        XCTAssertEqual(viewModel.focusDuration, AppConstants.focusDurationOptions[2])
        XCTAssertGreaterThan(emissionCount, 0, "更新 focusDuration 应触发 objectWillChange 发布")

        cancellable.cancel()
    }

    func testPublishedAutoStartBreaks_WhenToggled_ThenPublishesChange() {
        var emissionCount = 0
        let cancellable = viewModel.objectWillChange
            .sink { emissionCount += 1 }

        viewModel.autoStartBreaks = false

        XCTAssertFalse(viewModel.autoStartBreaks)
        XCTAssertGreaterThan(emissionCount, 0, "切换 autoStartBreaks 应触发 objectWillChange 发布")

        cancellable.cancel()
    }

    // ========================================================================
    // MARK: - 边界条件
    // ========================================================================

    func testLongBreakAfterRounds_PersistsChanges() {
        viewModel.longBreakAfterRounds = 6
        XCTAssertEqual(viewModel.longBreakAfterRounds, 6)
    }

    func testSoundEnabled_PersistsChanges() {
        viewModel.soundEnabled = false
        XCTAssertFalse(viewModel.soundEnabled)

        viewModel.soundEnabled = true
        XCTAssertTrue(viewModel.soundEnabled)
    }

    func testResetToDefaults_MultipleCalls_AreIdempotent() {
        viewModel.resetToDefaults()
        viewModel.resetToDefaults()

        XCTAssertEqual(viewModel.focusDuration, AppConstants.defaultFocusDuration)
    }

    // ========================================================================
    // MARK: - @AppStorage 收敛验证（T2 技术债）
    // 验证设置经 @AppStorage 持久化，可在实例间（模拟 App 重启）恢复
    // ========================================================================

    func testWeeklyReportEnabled_WhenChanged_ThenPersistsAcrossInstances() {
        // Given: 关闭周报开关
        viewModel.weeklyReportEnabled = false

        // When: 用全新实例读取（模拟 App 重启）
        let newVM = SettingsViewModel(syncService: MockSettingsSyncService())

        // Then: 应从 @AppStorage(UserDefaults) 恢复关闭状态
        XCTAssertFalse(newVM.weeklyReportEnabled)
    }

    func testWeeklyReportEnabled_WhenToggled_ThenPostsRemindersDataChanged() {
        var fired = false
        let observer = NotificationCenter.default.addObserver(
            forName: .remindersDataChanged, object: nil, queue: nil
        ) { _ in fired = true }

        viewModel.weeklyReportEnabled.toggle()

        XCTAssertTrue(fired, "切换周报开关应发出 remindersDataChanged 通知")
        NotificationCenter.default.removeObserver(observer)
    }

    func testColorSchemeOption_WhenSetDark_ThenPersistsAndDerivesDarkScheme() {
        viewModel.colorSchemeOption = "dark"

        let newVM = SettingsViewModel(syncService: MockSettingsSyncService())
        XCTAssertEqual(newVM.colorSchemeOption, "dark")
        XCTAssertEqual(newVM.preferredColorScheme, .dark)
    }

    // ========================================================================
    // MARK: - 习惯打卡提醒（A2）
    // ========================================================================

    func testHabitReminderEnabled_WhenChanged_ThenPersistsAcrossInstances() {
        // Given
        viewModel.habitReminderEnabled = true

        // When - 新实例读取（模拟 App 重启）
        let newVM = SettingsViewModel(syncService: MockSettingsSyncService())

        // Then - 从 @AppStorage 恢复
        XCTAssertTrue(newVM.habitReminderEnabled)
    }

    func testHabitReminderTime_WhenChanged_ThenPersistsAndKeepsEnabled() {
        // Given - 开启习惯提醒
        viewModel.habitReminderEnabled = true
        XCTAssertEqual(viewModel.habitReminderTime.hour, 20, "默认时间应为 20:00")

        // When - 修改为 08:30
        viewModel.habitReminderTime = DateComponents(hour: 8, minute: 30)

        // Then - 持久化且开关保持开启（时间变更时若已开启会重新调度，不崩溃）
        XCTAssertEqual(viewModel.habitReminderTime.hour, 8)
        XCTAssertEqual(viewModel.habitReminderTime.minute, 30)
        XCTAssertTrue(viewModel.habitReminderEnabled)

        let newVM = SettingsViewModel(syncService: MockSettingsSyncService())
        XCTAssertEqual(newVM.habitReminderTime.hour, 8, "时间应跨实例持久化")
        XCTAssertEqual(newVM.habitReminderTime.minute, 30)
    }

    func testResetToDefaults_ThenHabitReminderDisabledAndTimeReset() {
        // Given
        viewModel.habitReminderEnabled = true
        viewModel.habitReminderTime = DateComponents(hour: 7, minute: 15)

        // When
        viewModel.resetToDefaults()

        // Then
        XCTAssertFalse(viewModel.habitReminderEnabled, "重置后习惯提醒应关闭")
        XCTAssertEqual(viewModel.habitReminderTime.hour, 20, "重置后时间应回默认 20:00")
        XCTAssertEqual(viewModel.habitReminderTime.minute, 0)
    }
}

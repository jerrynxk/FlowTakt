import Foundation
import UserNotifications
import Combine

// MARK: - SettingsViewModel

final class SettingsViewModel: ObservableObject {
    /// 数据库重置回调（由 AppDependency 注入）
    var onResetDatabase: (() -> Bool)?

    // MARK: - Published 属性
    @Published var focusDuration: TimeInterval {
        didSet { UserDefaults.standard.set(focusDuration, forKey: "focusDuration") }
    }
    @Published var shortBreakDuration: TimeInterval {
        didSet { UserDefaults.standard.set(shortBreakDuration, forKey: "shortBreakDuration") }
    }
    @Published var longBreakDuration: TimeInterval {
        didSet { UserDefaults.standard.set(longBreakDuration, forKey: "longBreakDuration") }
    }
    @Published var longBreakAfterRounds: Int {
        didSet { UserDefaults.standard.set(longBreakAfterRounds, forKey: "longBreakAfterRounds") }
    }
    @Published var soundEnabled: Bool {
        didSet { UserDefaults.standard.set(soundEnabled, forKey: "soundEnabled") }
    }
    @Published var vibrationEnabled: Bool {
        didSet { UserDefaults.standard.set(vibrationEnabled, forKey: "vibrationEnabled") }
    }
    @Published var dailyReminderEnabled: Bool {
        didSet {
            UserDefaults.standard.set(dailyReminderEnabled, forKey: "dailyReminderEnabled")
            if dailyReminderEnabled {
                scheduleDailyReminder()
            } else {
                cancelDailyReminder()
            }
        }
    }
    @Published var dailyReminderTime: DateComponents {
        didSet { UserDefaults.standard.set(dailyReminderTime.hour, forKey: "reminderHour")
                UserDefaults.standard.set(dailyReminderTime.minute, forKey: "reminderMinute") }
    }
    @Published var iCloudSyncEnabled: Bool = true {
        didSet { UserDefaults.standard.set(iCloudSyncEnabled, forKey: "iCloudSyncEnabled") }
    }
    @Published var autoStartBreaks: Bool = true {
        didSet { UserDefaults.standard.set(autoStartBreaks, forKey: "autoStartBreaks") }
    }
    @Published var autoStartFocus: Bool = false {
        didSet { UserDefaults.standard.set(autoStartFocus, forKey: "autoStartFocus") }
    }
    @Published var appLanguage: String {
        didSet {
            UserDefaults.standard.set(appLanguage, forKey: "appLanguage")
        }
    }

    let languageOptions = ["zh-Hans", "en"]
    let languageNames = ["简体中文", "English"]

    @Published var selectedLanguageOption: Int = 0
    @Published var selectedFocusOption: Int = 1
    @Published var selectedShortBreakOption: Int = 1
    @Published var selectedLongBreakOption: Int = 2

    let focusOptions = AppConstants.focusDurationOptions
    let shortBreakOptions = AppConstants.shortBreakOptions
    let longBreakOptions = AppConstants.longBreakOptions

    init() {
        let defaults = UserDefaults.standard

        // 从 UserDefaults 加载或使用默认值
        focusDuration = defaults.double(forKey: "focusDuration").nonZeroElse(AppConstants.defaultFocusDuration)
        shortBreakDuration = defaults.double(forKey: "shortBreakDuration").nonZeroElse(AppConstants.defaultShortBreakDuration)
        longBreakDuration = defaults.double(forKey: "longBreakDuration").nonZeroElse(AppConstants.defaultLongBreakDuration)
        longBreakAfterRounds = defaults.integer(forKey: "longBreakAfterRounds").nonZeroElse(AppConstants.longBreakAfterRounds)
        soundEnabled = defaults.object(forKey: "soundEnabled") as? Bool ?? true
        vibrationEnabled = defaults.object(forKey: "vibrationEnabled") as? Bool ?? true
        dailyReminderEnabled = defaults.object(forKey: "dailyReminderEnabled") as? Bool ?? false
        iCloudSyncEnabled = defaults.object(forKey: "iCloudSyncEnabled") as? Bool ?? true
        autoStartBreaks = defaults.object(forKey: "autoStartBreaks") as? Bool ?? true
        autoStartFocus = defaults.object(forKey: "autoStartFocus") as? Bool ?? false
        appLanguage = defaults.string(forKey: "appLanguage") ?? "zh-Hans"

        let hour = defaults.integer(forKey: "reminderHour").nonZeroElse(9)
        let minute = defaults.integer(forKey: "reminderMinute")
        dailyReminderTime = DateComponents(hour: hour, minute: minute)

        selectedLanguageOption = languageOptions.firstIndex(of: appLanguage) ?? 0
        selectedFocusOption = focusOptions.firstIndex(of: focusDuration) ?? 1
        selectedShortBreakOption = shortBreakOptions.firstIndex(of: shortBreakDuration) ?? 1
        selectedLongBreakOption = longBreakOptions.firstIndex(of: longBreakDuration) ?? 2
    }

    // MARK: - 公开方法

    func updateFocusDuration(at index: Int) {
        guard index < focusOptions.count else { return }
        selectedFocusOption = index
        focusDuration = focusOptions[index]
    }

    func updateShortBreakDuration(at index: Int) {
        guard index < shortBreakOptions.count else { return }
        selectedShortBreakOption = index
        shortBreakDuration = shortBreakOptions[index]
    }

    func updateLongBreakDuration(at index: Int) {
        guard index < longBreakOptions.count else { return }
        selectedLongBreakOption = index
        longBreakDuration = longBreakOptions[index]
    }

    func updateLanguage(at index: Int) {
        guard index < languageOptions.count else { return }
        selectedLanguageOption = index
        appLanguage = languageOptions[index]
        L10n.shared.appLanguage = appLanguage
    }

    func resetToDefaults() {
        focusDuration = AppConstants.defaultFocusDuration
        shortBreakDuration = AppConstants.defaultShortBreakDuration
        longBreakDuration = AppConstants.defaultLongBreakDuration
        longBreakAfterRounds = AppConstants.longBreakAfterRounds
        soundEnabled = true
        vibrationEnabled = true
        dailyReminderEnabled = false
        iCloudSyncEnabled = true
        autoStartBreaks = true
        autoStartFocus = false
    }

    /// 重置数据库（清空所有数据）
    /// 通过 onResetDatabase 回调触发 PersistenceController 执行实际重置
    /// - Returns: true 表示重置成功，false 表示失败
    @discardableResult
    func resetDatabase() -> Bool {
        return onResetDatabase?() ?? false
    }

    // MARK: - 私有方法

    private func scheduleDailyReminder() {
        let content = UNMutableNotificationContent()
        content.title = L10n.shared.每日提醒标题
        content.body = L10n.shared.每日提醒内容
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: dailyReminderTime, repeats: true)
        let request = UNNotificationRequest(identifier: "daily_reminder", content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request)
    }

    private func cancelDailyReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["daily_reminder"])
    }
}

// MARK: - 辅助

private extension Int {
    func nonZeroElse(_ fallback: Int) -> Int {
        return self > 0 ? self : fallback
    }
}

private extension Double {
    func nonZeroElse(_ fallback: Double) -> Double {
        return self > 0 ? self : fallback
    }
}

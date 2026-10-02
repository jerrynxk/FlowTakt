import Foundation
import UserNotifications
import Combine
import UIKit
import SwiftUI

// MARK: - SettingsViewModel

final class SettingsViewModel: ObservableObject {
    /// 数据库重置回调（由 AppDependency 注入）
    var onResetDatabase: ((@escaping (Bool) -> Void) -> Void)?

    /// 同步服务（构造时注入，避免后续破坏不可变性）
    private let syncService: SyncServiceProtocol

    // MARK: - 持久化设置
    // 收敛至 @AppStorage：存储交给系统 UserDefaults（SwiftUI 原生桥接），
    // 计算属性在 set 时显式 objectWillChange.send() 以保证 SwiftUI 刷新
    // （规避 ObservableObject 内 @AppStorage 不自动刷新陷阱）。

    @AppStorage("focusDuration") private var focusDurationStorage: Double = AppConstants.defaultFocusDuration
    var focusDuration: Double {
        get { focusDurationStorage }
        set { objectWillChange.send(); focusDurationStorage = newValue }
    }

    @AppStorage("shortBreakDuration") private var shortBreakDurationStorage: Double = AppConstants.defaultShortBreakDuration
    var shortBreakDuration: Double {
        get { shortBreakDurationStorage }
        set { objectWillChange.send(); shortBreakDurationStorage = newValue }
    }

    @AppStorage("longBreakDuration") private var longBreakDurationStorage: Double = AppConstants.defaultLongBreakDuration
    var longBreakDuration: Double {
        get { longBreakDurationStorage }
        set { objectWillChange.send(); longBreakDurationStorage = newValue }
    }

    @AppStorage("longBreakAfterRounds") private var longBreakAfterRoundsStorage: Int = AppConstants.longBreakAfterRounds
    var longBreakAfterRounds: Int {
        get { longBreakAfterRoundsStorage }
        set { objectWillChange.send(); longBreakAfterRoundsStorage = newValue }
    }

    @AppStorage("soundEnabled") private var soundEnabledStorage: Bool = true
    var soundEnabled: Bool {
        get { soundEnabledStorage }
        set { objectWillChange.send(); soundEnabledStorage = newValue }
    }

    @AppStorage("vibrationEnabled") private var vibrationEnabledStorage: Bool = true
    var vibrationEnabled: Bool {
        get { vibrationEnabledStorage }
        set { objectWillChange.send(); vibrationEnabledStorage = newValue }
    }

    @AppStorage("speechEnabled") private var speechEnabledStorage: Bool = true
    var speechEnabled: Bool {
        get { speechEnabledStorage }
        set { objectWillChange.send(); speechEnabledStorage = newValue }
    }

    @AppStorage("autoStartBreaks") private var autoStartBreaksStorage: Bool = true
    var autoStartBreaks: Bool {
        get { autoStartBreaksStorage }
        set { objectWillChange.send(); autoStartBreaksStorage = newValue }
    }

    @AppStorage("autoStartFocus") private var autoStartFocusStorage: Bool = false
    var autoStartFocus: Bool {
        get { autoStartFocusStorage }
        set { objectWillChange.send(); autoStartFocusStorage = newValue }
    }

    @AppStorage("weeklyReportEnabled") private var weeklyReportEnabledStorage: Bool = true
    var weeklyReportEnabled: Bool {
        get { weeklyReportEnabledStorage }
        set {
            objectWillChange.send()
            weeklyReportEnabledStorage = newValue
            // 触发 ReminderService 重排（内部按开关注册/取消周报）
            NotificationCenter.default.post(name: .remindersDataChanged, object: nil)
        }
    }

    /// 语言（单源：直接读写 L10n 单例，避免 @AppStorage 默认值与 L10n 首启跟随系统不一致）
    var appLanguage: String {
        get { L10n.shared.appLanguage }
        set { objectWillChange.send(); L10n.shared.appLanguage = newValue }
    }

    @AppStorage("colorSchemeOption") private var colorSchemeOptionStorage: String = "system"
    var colorSchemeOption: String {
        get { colorSchemeOptionStorage }
        set { objectWillChange.send(); colorSchemeOptionStorage = newValue }
    }

    @AppStorage("iCloudSyncEnabled") private var iCloudSyncEnabledStorage: Bool = false
    var iCloudSyncEnabled: Bool {
        get { iCloudSyncEnabledStorage }
        set {
            objectWillChange.send()
            iCloudSyncEnabledStorage = newValue
            if iCloudSyncEnabledStorage { syncService.forceSync() }
        }
    }

    @AppStorage("dailyReminderEnabled") private var dailyReminderEnabledStorage: Bool = false
    var dailyReminderEnabled: Bool {
        get { dailyReminderEnabledStorage }
        set {
            objectWillChange.send()
            dailyReminderEnabledStorage = newValue
            if newValue { scheduleDailyReminder() } else { cancelDailyReminder() }
        }
    }

    @AppStorage("reminderHour") private var reminderHourStorage: Int = 9
    @AppStorage("reminderMinute") private var reminderMinuteStorage: Int = 0
    var dailyReminderTime: DateComponents {
        get { DateComponents(hour: reminderHourStorage, minute: reminderMinuteStorage) }
        set {
            objectWillChange.send()
            reminderHourStorage = newValue.hour ?? 9
            reminderMinuteStorage = newValue.minute ?? 0
            // 审查修复（2026-08-12）：时间变更时若已开启，重新调度使新时间即时生效
            // （与 habitReminderTime setter 行为对齐；否则开启状态下改时间不生效）
            if dailyReminderEnabledStorage {
                scheduleDailyReminder()
            }
        }
    }

    @AppStorage("habitReminderEnabled") private var habitReminderEnabledStorage: Bool = false
    var habitReminderEnabled: Bool {
        get { habitReminderEnabledStorage }
        set {
            objectWillChange.send()
            habitReminderEnabledStorage = newValue
            if newValue { scheduleHabitReminder() } else { cancelHabitReminder() }
        }
    }

    @AppStorage("habitReminderHour") private var habitReminderHourStorage: Int = 20
    @AppStorage("habitReminderMinute") private var habitReminderMinuteStorage: Int = 0
    var habitReminderTime: DateComponents {
        get { DateComponents(hour: habitReminderHourStorage, minute: habitReminderMinuteStorage) }
        set {
            objectWillChange.send()
            habitReminderHourStorage = newValue.hour ?? 20
            habitReminderMinuteStorage = newValue.minute ?? 0
            // 时间变更时若已开启，重新调度使新时间即时生效
            if habitReminderEnabledStorage {
                scheduleHabitReminder()
            }
        }
    }

    // MARK: - 外观

    /// 派生：SwiftUI ColorScheme？
    var preferredColorScheme: ColorScheme? {
        switch colorSchemeOption {
        case "light":  return .light
        case "dark":   return .dark
        default:       return nil  // 跟随系统
        }
    }

    // MARK: - 通知与后台刷新状态

    /// 系统通知授权状态
    @Published var notificationStatus: UNAuthorizationStatus = .notDetermined
    /// 后台 App 刷新状态（系统设置项，仅可读取，无法在 App 内请求）
    @Published var backgroundRefreshStatus: UIBackgroundRefreshStatus = .restricted

    let languageOptions = ["zh-Hans", "en"]
    let languageNames = ["简体中文", "English"]

    @Published var selectedLanguageOption: Int = 0
    @Published var selectedFocusOption: Int = 1
    @Published var selectedShortBreakOption: Int = 1
    @Published var selectedLongBreakOption: Int = 2

    let focusOptions = AppConstants.focusDurationOptions
    let shortBreakOptions = AppConstants.shortBreakOptions
    let longBreakOptions = AppConstants.longBreakOptions

    init(syncService: SyncServiceProtocol) {
        self.syncService = syncService

        // 派生选择器索引（基于 @AppStorage 已加载的持久化值）
        selectedLanguageOption = languageOptions.firstIndex(of: appLanguage) ?? 0
        selectedFocusOption = focusOptions.firstIndex(of: focusDuration) ?? 1
        selectedShortBreakOption = shortBreakOptions.firstIndex(of: shortBreakDuration) ?? 1
        selectedLongBreakOption = longBreakOptions.firstIndex(of: longBreakDuration) ?? 2

        // 读取后台 App 刷新状态（系统设置项，仅可读取不可请求）
        backgroundRefreshStatus = UIApplication.shared.backgroundRefreshStatus
        // 异步读取通知授权状态
        refreshNotificationStatus()
    }

    // MARK: - 公开方法

    func updateFocusDuration(at index: Int) {
        guard focusOptions.indices.contains(index) else { return }
        selectedFocusOption = index
        focusDuration = focusOptions[index]
    }

    func updateShortBreakDuration(at index: Int) {
        guard shortBreakOptions.indices.contains(index) else { return }
        selectedShortBreakOption = index
        shortBreakDuration = shortBreakOptions[index]
    }

    func updateLongBreakDuration(at index: Int) {
        guard longBreakOptions.indices.contains(index) else { return }
        selectedLongBreakOption = index
        longBreakDuration = longBreakOptions[index]
    }

    func updateLanguage(at index: Int) {
        guard languageOptions.indices.contains(index) else { return }
        selectedLanguageOption = index
        appLanguage = languageOptions[index]
        L10n.shared.appLanguage = appLanguage
    }

    /// 恢复默认设置：重置全部 @AppStorage 持久化键（与各键默认值一致），
    /// 并重新派生选择器索引，保证 UI 显示与存储值同步。
    func resetToDefaults() {
        objectWillChange.send()
        focusDuration = AppConstants.defaultFocusDuration
        shortBreakDuration = AppConstants.defaultShortBreakDuration
        longBreakDuration = AppConstants.defaultLongBreakDuration
        longBreakAfterRounds = AppConstants.longBreakAfterRounds
        soundEnabled = true
        vibrationEnabled = true
        speechEnabled = true
        weeklyReportEnabled = true
        autoStartBreaks = true
        autoStartFocus = false
        dailyReminderEnabled = false
        habitReminderEnabled = false
        iCloudSyncEnabled = false
        appLanguage = "zh-Hans"
        colorSchemeOption = "system"
        reminderHourStorage = 9
        reminderMinuteStorage = 0
        habitReminderHourStorage = 20
        habitReminderMinuteStorage = 0

        // 重新派生选择器索引，保持 UI 与存储值一致
        selectedLanguageOption = languageOptions.firstIndex(of: appLanguage) ?? 0
        selectedFocusOption = focusOptions.firstIndex(of: focusDuration) ?? 1
        selectedShortBreakOption = shortBreakOptions.firstIndex(of: shortBreakDuration) ?? 1
        selectedLongBreakOption = longBreakOptions.firstIndex(of: longBreakDuration) ?? 2
    }

    /// 重置数据库（清空所有数据）
    /// 通过 onResetDatabase 回调触发 PersistenceController 执行实际重置（异步，避免主线程阻塞）
    func resetDatabase(completion: @escaping (Bool) -> Void) {
        onResetDatabase?(completion) ?? completion(false)
    }

    /// 手动触发 iCloud 同步（封装内部 syncService，避免暴露依赖）
    func forceSync() {
        syncService.forceSync()
    }

    // MARK: - 通知与后台刷新

    /// 重新读取系统通知授权状态
    func refreshNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                self?.notificationStatus = settings.authorizationStatus
            }
        }
    }

    /// 跳转到系统设置（用于开启通知权限 / 后台 App 刷新）
    func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    /// 通知是否已授权（含 provisional 临时授权）
    var isNotificationAuthorized: Bool {
        notificationStatus == .authorized || notificationStatus == .provisional
    }

    /// 通知状态文案
    var notificationStatusText: String {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral:
            return L10n.shared.通知已授权
        case .denied:
            return L10n.shared.通知未授权
        default:
            return L10n.shared.通知尚未请求
        }
    }

    /// 后台 App 刷新状态文案
    var backgroundRefreshStatusText: String {
        switch backgroundRefreshStatus {
        case .available:
            return L10n.shared.后台刷新可用
        case .denied:
            return L10n.shared.后台刷新不可用
        case .restricted:
            return L10n.shared.后台刷新受限
        @unknown default:
            return L10n.shared.后台刷新受限
        }
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

    private func scheduleHabitReminder() {
        let content = UNMutableNotificationContent()
        content.title = L10n.shared.习惯打卡提醒标题
        content.body = L10n.shared.习惯打卡提醒内容
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: habitReminderTime, repeats: true)
        let request = UNNotificationRequest(identifier: "habit_daily_reminder", content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request)
    }

    private func cancelHabitReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["habit_daily_reminder"])
    }
}

// MARK: - 辅助
// nonZeroElse 已提取到 Extensions/Numeric+Extensions.swift

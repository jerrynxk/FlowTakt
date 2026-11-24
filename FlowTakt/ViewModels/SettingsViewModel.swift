import Foundation
import UserNotifications
import Combine
import UIKit
import SwiftUI

// MARK: - SettingsViewModel

/// 未注入重置回调时的失败原因
enum ResetUnavailableError: LocalizedError {
    case callbackMissing
    var errorDescription: String? { L10n.shared.重置数据库失败提示 }
}

final class SettingsViewModel: ObservableObject {
    /// 数据库重置回调（由 AppDependency 注入）
    var onResetDatabase: ((@escaping (Result<Void, Error>) -> Void) -> Void)?

    /// iCloud 同步切换回调（由 AppDependency 注入，2026-10-15 审查 P0-1）。
    /// 运行时重载 store 以真正挂载/卸载 CloudKit；失败时回滚开关并设置 `cloudSyncError`。
    /// 未注入时（Preview/测试）退化为旧行为：仅写 UserDefaults，下次冷启动生效。
    var onCloudSyncChanged: ((Bool, @escaping (Result<Void, Error>) -> Void) -> Void)?

    /// iCloud 同步切换失败的具体原因（禁止笼统「切换失败」）
    @Published var cloudSyncError: String?

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

    /// 专注开始时是否自动播放白噪音（用户反馈 2026-11-19）。
    /// 键收口到 `FocusViewModel.whiteNoiseAutoPlayKey`（单一来源，避免两处字面量漂移）：
    /// 专注页手动关闭白噪音时会写 false，此后开始专注不再自动播放；在此重新打开则恢复。
    @AppStorage(FocusViewModel.whiteNoiseAutoPlayKey) private var autoPlayWhiteNoiseStorage: Bool = true
    var autoPlayWhiteNoise: Bool {
        get { autoPlayWhiteNoiseStorage }
        set { objectWillChange.send(); autoPlayWhiteNoiseStorage = newValue }
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

    /// iCloud 同步开关。**默认开启**（用户反馈 2026-11-19：希望自动同步，而不是先手动打开）。
    /// 判据与 `PersistenceController.isCloudSyncEnabledByUser` 共用同一键与同一默认值，
    /// 避免「UI 显示关、实际在同步」或反之的假说明。
    @AppStorage("iCloudSyncEnabled") private var iCloudSyncEnabledStorage: Bool = true
    var iCloudSyncEnabled: Bool {
        get { iCloudSyncEnabledStorage }
        set {
            objectWillChange.send()
            iCloudSyncEnabledStorage = newValue
            if let apply = onCloudSyncChanged {
                // 修复（2026-10-15 审查 P0-1）：仅写 UserDefaults 时 CloudKit 不会挂载
                // （init 只在启动时读一次）→ 开关形同虚设。改为运行时重载 store。
                apply(newValue) { [weak self] result in
                    guard let self else { return }
                    switch result {
                    case .success:
                        self.cloudSyncError = nil
                    case .failure(let error):
                        // 失败回滚开关并如实回显原因（禁止笼统报错）
                        self.objectWillChange.send()
                        self.iCloudSyncEnabledStorage = !newValue
                        self.cloudSyncError = error.localizedDescription
                    }
                }
            } else if newValue {
                // 回调未注入（Preview/测试环境）：UserDefaults 已写，下次冷启动生效
                syncService.forceSync()
            }
        }
    }

    @AppStorage("dailyReminderEnabled") private var dailyReminderEnabledStorage: Bool = false
    var dailyReminderEnabled: Bool {
        get { dailyReminderEnabledStorage }
        set {
            // 修复（2026-10-15 通知乱弹）：SwiftUI 的 `Toggle(isOn: $viewModel.dailyReminderEnabled)`
            // 会在视图重建时写回绑定值。旧实现无条件调度/取消，导致设置页每次重建都
            // 重复 add 同一条「每日提醒」并重置其触发基准。仅在**值真正变化**时才动通知系统。
            let changed = dailyReminderEnabledStorage != newValue
            objectWillChange.send()
            dailyReminderEnabledStorage = newValue
            guard changed else { return }
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
            // 同 dailyReminderEnabled：仅在值真正变化时动通知系统（修复 2026-10-15 通知乱弹）
            let changed = habitReminderEnabledStorage != newValue
            objectWillChange.send()
            habitReminderEnabledStorage = newValue
            guard changed else { return }
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
        autoPlayWhiteNoise = true
        weeklyReportEnabled = true
        autoStartBreaks = true
        autoStartFocus = false
        dailyReminderEnabled = false
        habitReminderEnabled = false
        // iCloud 同步默认开启（2026-11-19 用户反馈）：恢复默认即恢复「自动同步」
        iCloudSyncEnabled = true
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
    ///
    /// 修复（2026-10-14）：改为返回 `Result`，让 UI 能区分「云端副本没删掉」
    /// 与「本地销毁失败」——两者对用户是完全不同的处置动作，不能笼统报「重置失败」。
    /// iCloud 开启时会先清除 CloudKit 镜像记录，云端清除失败即中止，本地数据保持原样。
    func resetDatabase(completion: @escaping (Result<Void, Error>) -> Void) {
        guard let onResetDatabase else {
            completion(.failure(ResetUnavailableError.callbackMissing))
            return
        }
        onResetDatabase(completion)
    }

    /// 手动触发 iCloud 同步（封装内部 syncService，避免暴露依赖）
    /// 返回真实结果供 UI 如实反馈（用户反馈 2026-11-17：消除"同步请求已发送"假说明）
    @discardableResult
    func forceSync() -> SyncOutcome {
        syncService.forceSync()
    }

    /// 手动同步（2026-11-19 修复）：先刷新 iCloud 账户状态快照再执行，结果异步返回。
    /// 同步按钮统一走本入口 —— 旧 forceSync 读启动时的一次性快照，
    /// 重登 iCloud 后不重启 App 恒报「账户不可用」（用户实测命中）。
    func syncNow(completion: @escaping (SyncOutcome) -> Void) {
        syncService.syncNow(completion: completion)
    }

    /// 同步状态文案（用户反馈 2026-11-19）：如实反映「已挂载自动同步」「尚未检测完成」
    /// 「账户不可用」「已关闭」四种状态，不把「开关为开」谎称为「已同步」，
    /// 也不把「store 仍在加载」误报成「账户不可用」。
    var cloudSyncStatusText: String {
        guard iCloudSyncEnabled else { return L10n.shared.同步状态已关闭 }
        switch syncService.mountStatus {
        case .available:     return L10n.shared.同步状态自动
        case .notDetermined: return L10n.shared.同步状态检测中
        case .unavailable:   return L10n.shared.同步状态账户不可用
        }
    }

    /// 状态行的图标（语义与文案一一对应）
    var cloudSyncStatusIcon: String {
        guard iCloudSyncEnabled else { return "icloud.slash" }
        switch syncService.mountStatus {
        case .available:     return "checkmark.icloud"
        case .notDetermined: return "icloud"
        case .unavailable:   return "exclamationmark.icloud"
        }
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

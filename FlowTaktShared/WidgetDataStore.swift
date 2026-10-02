import Foundation

// MARK: - 小组件共享数据模型

/// 单条提醒在 App Group 快照中的表示（可编码，供 Widget 直接读取）
struct WidgetReminder: Codable, Identifiable {
    let id: String
    let title: String
    let categoryRaw: String
    let colorHex: String?
    /// 下一次发生的日期（生日/纪念日为下一个对应的月/日；拜访/事件为原定日期）
    let nextDate: Date
    let isAllDay: Bool
}

/// 写入 App Group 的快照（主 App 生成，Widget 读取）
struct WidgetSnapshot: Codable {
    let reminders: [WidgetReminder]
    let updatedAt: Date
}

// MARK: - App Group 数据读写

/// 主 App 与 Widget Extension 通过 App Group 共享「未来临近提醒」快照。
/// 主 App 在提醒数据变更后写入；Widget 的 TimelineProvider 读取并展示。
struct WidgetDataStore {
    /// App Group 标识（须与 entitlements 中一致）
    /// 同步更新 FlowTakt/Utils/Constants.swift 中的 appGroupIdentifier
    static let appGroupID = "group.com.flowtakt"
    /// 快照存储键
    static let snapshotKey = "flowtakt_reminder_snapshot"
    /// 语言偏好键（主 App 写入，Widget 读取以保持一致的语言显示）
    static let languageKey = "appLanguage"

    /// 写入快照到 App Group 共享 UserDefaults
    static func write(_ snapshot: WidgetSnapshot) {
        do {
            let data = try JSONEncoder().encode(snapshot)
            let defaults = UserDefaults(suiteName: appGroupID)
            defaults?.set(data, forKey: snapshotKey)
        } catch {
            print("⚠️ WidgetDataStore 写入失败：\(error.localizedDescription)")
        }
    }

    /// 从 App Group 读取快照
    static func read() -> WidgetSnapshot? {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// 写入语言偏好（主 App 语言切换时调用，供 Widget 端保持语言一致）
    static func writeLanguage(_ language: String) {
        UserDefaults(suiteName: appGroupID)?.set(language, forKey: languageKey)
    }

    /// 读取语言偏好；无记录时返回 nil（Widget 端回退到系统语言）
    static func readLanguage() -> String? {
        UserDefaults(suiteName: appGroupID)?.string(forKey: languageKey)
    }

    /// 今日专注摘要键（供锁屏 Widget「今日专注」模式读取）
    static let focusSummaryKey = "flowtakt_focus_summary"

    /// 今日专注摘要（主 App 统计后写入，锁屏 Widget 读取）
    struct FocusSummary: Codable {
        let completedPomodoros: Int
        let totalMinutes: Int
        let updatedAt: Date
    }

    /// 写入今日专注摘要到 App Group
    static func writeFocusSummary(_ summary: FocusSummary) {
        do {
            let data = try JSONEncoder().encode(summary)
            UserDefaults(suiteName: appGroupID)?.set(data, forKey: focusSummaryKey)
        } catch {
            print("⚠️ WidgetDataStore 写入焦点摘要失败：\(error.localizedDescription)")
        }
    }

    /// 从 App Group 读取今日专注摘要
    static func readFocusSummary() -> FocusSummary? {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: focusSummaryKey) else { return nil }
        return try? JSONDecoder().decode(FocusSummary.self, from: data)
    }
}

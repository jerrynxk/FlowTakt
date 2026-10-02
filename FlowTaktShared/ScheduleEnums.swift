import Foundation

// MARK: - 共享语言偏好

/// Widget/共享模块的语言判断：优先读 App Group（与主 App 中英切换一致），
/// 无记录时回退系统语言（与主 App L10n 首启行为一致，避免中英混排）
enum WidgetLanguage {
    static var isEnglish: Bool {
        if let language = WidgetDataStore.readLanguage() {
            return language.hasPrefix("en")
        }
        let preferred = Locale.preferredLanguages.first ?? "zh-Hans"
        return preferred.hasPrefix("en")
    }
}

// MARK: - 日程分类

/// 日程/提醒分类。定义于共享模块，主 App 与 Widget 双端共用。
enum ScheduleCategory: String, Codable, CaseIterable, Identifiable {
    case event = "event"
    case birthday = "birthday"
    case anniversary = "anniversary"
    case visit = "visit"

    var id: String { rawValue }

    /// 系统图标
    var iconName: String {
        switch self {
        case .event:       return "calendar"
        case .birthday:    return "gift.fill"
        case .anniversary: return "heart.fill"
        case .visit:       return "person.2.fill"
        }
    }

    /// 是否按年重复（生日/纪念日每年触发）
    var repeatsYearly: Bool {
        self == .birthday || self == .anniversary
    }

    /// 本地化显示名（轻量实现，不依赖主 App 的 L10n）
    /// 语言偏好从 App Group UserDefaults 读取，无记录时回退系统语言
    var displayName: String {
        let isEnglish = WidgetLanguage.isEnglish
        switch self {
        case .event:       return isEnglish ? "Event" : "事件"
        case .birthday:    return isEnglish ? "Birthday" : "生日"
        case .anniversary: return isEnglish ? "Anniversary" : "纪念日"
        case .visit:       return isEnglish ? "Client Visit" : "客户拜访"
        }
    }
}

// MARK: - 重复规则

enum RepeatRule: String, Codable, CaseIterable {
    case none = "none"
    case yearly = "yearly"
}

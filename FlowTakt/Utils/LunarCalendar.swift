import Foundation

// MARK: - 农历日历工具

/// 农历日期工具，基于系统 Chinese Calendar 实现
/// 审查说明（2026-08-12）：iOS 16 部署目标下 Calendar.Component.isLeapMonth 不可用
/// （仅 iOS 17+ 提供），闰月无「闰」前缀为有意降级（#available 已保护，不会崩溃）。
struct LunarCalendar {

    /// 农历月份名称（1-based; [0] 为空占位）
    /// 注意：与 Date+Extensions.swift 中的 lunarMonths 数组重复。LunarCalendar 弃用后将统一到 Date+Extensions。
    private static let monthNames = [
        "", "正月", "二月", "三月", "四月", "五月", "六月",
        "七月", "八月", "九月", "十月", "冬月", "腊月"
    ]

    /// 农历日期名称（1-30）
    private static let dayNames = [
        "", "初一", "初二", "初三", "初四", "初五",
        "初六", "初七", "初八", "初九", "初十",
        "十一", "十二", "十三", "十四", "十五",
        "十六", "十七", "十八", "十九", "二十",
        "廿一", "廿二", "廿三", "廿四", "廿五",
        "廿六", "廿七", "廿八", "廿九", "三十"
    ]

    /// 农历专用日历（缓存）
    private static let calendar = Calendar(identifier: .chinese)

    // MARK: - 公开方法

    /// 将公历日期转换为农历日期字符串（如"冬月初九"）
    static func lunarDateString(from date: Date) -> String? {
        let calendar = Self.calendar

        var componentSet: Set<Calendar.Component> = [.year, .month, .day]
        if #available(iOS 17, *) {
            componentSet.insert(.isLeapMonth)
        }
        let components = calendar.dateComponents(componentSet, from: date)

        guard let month = components.month,
              let day = components.day,
              month >= 1, month <= 12,
              day >= 1, day <= 30 else {
            return nil
        }

        // 处理闰月
        var leapPrefix = ""
        if #available(iOS 17, *) {
            if components.isLeapMonth == true {
                leapPrefix = "闰"
            }
        }
        let monthName = "\(leapPrefix)\(monthNames[month])"

        // 农历每月首日特殊处理
        if day == 1 {
            return monthName  // 如"正月初一" → "正月"
        }

        return "\(monthName)\(dayNames[day])"
    }
}

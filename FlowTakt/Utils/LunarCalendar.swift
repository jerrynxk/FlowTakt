import Foundation

// MARK: - 农历日历工具

/// 农历日期工具，基于系统 Chinese Calendar 实现
struct LunarCalendar {

    /// 农历月份名称
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

    /// 干支年
    private static let tianGan = ["甲", "乙", "丙", "丁", "戊", "己", "庚", "辛", "壬", "癸"]
    private static let diZhi   = ["子", "丑", "寅", "卯", "辰", "巳", "午", "未", "申", "酉", "戌", "亥"]
    private static let shengXiao = ["鼠", "牛", "虎", "兔", "龙", "蛇", "马", "羊", "猴", "鸡", "狗", "猪"]

    // MARK: - 公开方法

    /// 将公历日期转换为农历日期字符串（如"冬月初九"）
    static func lunarDateString(from date: Date) -> String? {
        let calendar = Calendar(identifier: .chinese)

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

    /// 获取干支纪年字符串（如"甲辰"）
    static func ganzhiYear(from date: Date) -> String? {
        let calendar = Calendar(identifier: .chinese)
        let year = calendar.component(.year, from: date)
        let tgIndex = (year - 1) % 10
        let dzIndex = (year - 1) % 12
        return "\(tianGan[tgIndex])\(diZhi[dzIndex])"
    }

    /// 获取生肖
    static func shengXiao(from date: Date) -> String? {
        let calendar = Calendar(identifier: .chinese)
        let year = calendar.component(.year, from: date)
        let index = (year - 1) % 12
        return shengXiao[index]
    }

    /// 获取完整的农历日期信息（干支年 + 生肖 + 月 + 日）
    static func fullLunarString(from date: Date) -> String? {
        guard let lunarDate = lunarDateString(from: date),
              let ganzhi = ganzhiYear(from: date),
              let animal = shengXiao(from: date) else {
            return nil
        }
        return "\(ganzhi)\(animal)年 \(lunarDate)"
    }
}

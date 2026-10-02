import Foundation

// MARK: - 日期扩展

extension Date {
    // MARK: - 缓存

    /// 农历专用日历
    private static let chineseCalendar = Calendar(identifier: .chinese)

    /// 简短日期格式化器 (MM/dd)
    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM/dd"
        return f
    }()

    /// 完整日期格式化器 (yyyy/MM/dd)
    private static let fullDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy/MM/dd"
        return f
    }()

    // MARK: - 日期计算
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }

    /// 获取今天的结束边界：返回「次日 00:00:00」（半开区间语义）。
    /// 区间判断应使用 `date >= startOfDay && date < endOfDay`，
    /// 避免旧实现（23:59:59.0）漏掉当天最后一秒内的记录。
    var endOfDay: Date {
        let start = startOfDay
        guard let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: start) else {
            return start.addingTimeInterval(86400)
        }
        return nextDay
    }

    /// 获取本月的起始时间
    var startOfMonth: Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: self)
        guard let date = calendar.date(from: components) else {
            return startOfDay
        }
        return date
    }

    /// 格式化为简短日期字符串
    var shortDateString: String {
        Self.shortDateFormatter.string(from: self)
    }

    /// 格式化为完整日期字符串
    var fullDateString: String {
        Self.fullDateFormatter.string(from: self)
    }

    /// 今天是否与另一个日期位于同一天
    func isSameDay(as date: Date) -> Bool {
        Calendar.current.isDate(self, inSameDayAs: date)
    }

    /// 是否在今天
    var isToday: Bool {
        isSameDay(as: Date())
    }

    /// 是否在昨天
    var isYesterday: Bool {
        guard let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) else {
            return false
        }
        return isSameDay(as: yesterday)
    }

    // MARK: - 农历

    /// 农历日名称（如初一、十五、廿三等）
    var lunarDayText: String {
        let day = Self.chineseCalendar.component(.day, from: self)

        let lunarDayNames = [
            "初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
            "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
            "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十"
        ]

        guard day >= 1 && day <= 30 else { return "" }
        return lunarDayNames[day - 1]
    }

    /// 农历月份名（正月、二月...冬月、腊月）
    var lunarMonthText: String {
        let month = Self.chineseCalendar.component(.month, from: self)

        let lunarMonths = [
            "正月", "二月", "三月", "四月", "五月", "六月",
            "七月", "八月", "九月", "十月", "冬月", "腊月"
        ]

        guard month >= 1 && month <= 12 else { return "" }
        return lunarMonths[month - 1]
    }

    /// 日历格中显示的农历文本（初一显示月份名，其余显示日名）
    var lunarCellText: String {
        let day = Self.chineseCalendar.component(.day, from: self)
        return day == 1 ? lunarMonthText : lunarDayText
    }
}

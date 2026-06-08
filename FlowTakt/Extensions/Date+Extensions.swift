import Foundation

// MARK: - 日期扩展

extension Date {
    /// 获取今天的起始时间（00:00:00）
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }

    /// 获取今天的结束时间（23:59:59）
    var endOfDay: Date {
        let start = startOfDay
        return Calendar.current.date(byAdding: .day, value: 1, to: start)!
            .addingTimeInterval(-1)
    }

    /// 获取本周的起始时间（周一 00:00:00）
    var startOfWeek: Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: self)
        return calendar.date(from: components)!
    }

    /// 获取本月的起始时间
    var startOfMonth: Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: self)
        return calendar.date(from: components)!
    }

    /// 格式化为简短日期字符串
    var shortDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd"
        return formatter.string(from: self)
    }

    /// 格式化为完整日期字符串
    var fullDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter.string(from: self)
    }

    /// 格式化为时间字符串（HH:mm）
    var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: self)
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
        isSameDay(as: Calendar.current.date(byAdding: .day, value: -1, to: Date())!)
    }
}

import Foundation
import CoreData

extension ScheduleItem {
    /// 时间范围描述
    var timeRangeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        if isAllDay {
            return "全天"
        }
        if let end = endDate {
            return "\(formatter.string(from: startDate)) - \(formatter.string(from: end))"
        }
        return formatter.string(from: startDate)
    }
    
    /// 日期简短描述
    var dateText: String {
        if Calendar.current.isDateInToday(startDate) {
            return "今天"
        }
        if Calendar.current.isDateInTomorrow(startDate) {
            return "明天"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd"
        return formatter.string(from: startDate)
    }
}

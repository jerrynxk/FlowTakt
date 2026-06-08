import Foundation
import CoreData

extension HabitRecord {
    /// 日期简短描述
    var dateText: String {
        if Calendar.current.isDateInToday(date) { return "今天" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd"
        return formatter.string(from: date)
    }
}

import Foundation
import CoreData

extension HabitRecord {
    /// 日期简短描述（审查修复：复用 Date.shortDateString，删除重复的 MM/dd formatter）
    var dateText: String {
        if Calendar.current.isDateInToday(date) { return L10n.shared.今日 }
        return date.shortDateString
    }
}

import Foundation
import CoreData

extension Habit {
    /// 今天是否已打卡
    var isCheckedInToday: Bool {
        let todayStart = Date().startOfDay
        let todayEnd = Date().endOfDay
        return records.contains { $0.date >= todayStart && $0.date <= todayEnd }
    }
    
    /// 今天打卡次数
    var todayCount: Int16 {
        let todayStart = Date().startOfDay
        let todayEnd = Date().endOfDay
        return records
            .filter { $0.date >= todayStart && $0.date <= todayEnd }
            .reduce(0) { $0 + $1.count }
    }
    
    /// 频率显示文本
    var frequencyText: String {
        switch frequency {
        case "daily": return "每天"
        case "weekly": return "每周"
        case "monthly": return "每月"
        default: return frequency
        }
    }
}

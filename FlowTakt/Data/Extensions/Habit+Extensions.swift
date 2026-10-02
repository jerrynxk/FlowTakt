import Foundation
import CoreData

extension Habit {
    /// 今天是否已打卡（半开区间 [今日0点, 次日0点)，覆盖当日最后一秒）
    var isCheckedInToday: Bool {
        let todayStart = Date().startOfDay
        let todayEnd = Date().endOfDay
        return records.contains { $0.date >= todayStart && $0.date < todayEnd }
    }
    
    /// 今天打卡次数（半开区间）
    /// 审查修复（2026-08-12）：原 &+ 回绕加法在极端数据下静默出错；改用 Int32 累加 + 上限钳制
    var todayCount: Int16 {
        let todayStart = Date().startOfDay
        let todayEnd = Date().endOfDay
        var total: Int32 = 0
        for record in records {
            if record.date >= todayStart && record.date < todayEnd {
                total += Int32(record.count)
            }
        }
        return Int16(min(total, Int32(Int16.max)))
    }
    
    /// 频率显示文本
    var frequencyText: String {
        switch frequency {
        case "daily": return L10n.shared.每天
        case "weekly": return L10n.shared.每周
        case "monthly": return L10n.shared.每月
        default: return frequency
        }
    }
}

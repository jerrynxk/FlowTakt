import Foundation
import CoreData

extension TimeRecord {
    /// 格式化后的时长文本
    var durationText: String {
        let totalMinutes = Int(duration) / 60
        if totalMinutes >= 60 {
            let hours = totalMinutes / 60
            let mins = totalMinutes % 60
            if mins > 0 { return "\(hours)h \(mins)m" }
            return "\(hours)h"
        }
        return "\(totalMinutes)m"
    }
    
    /// 时间范围文本
    var timeRangeText: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        let start = f.string(from: startTime)
        if let end = endTime { return "\(start) - \(f.string(from: end))" }
        return start
    }
}

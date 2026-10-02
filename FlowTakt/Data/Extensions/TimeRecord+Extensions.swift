import Foundation
import CoreData

extension TimeRecord {
    // MARK: - 缓存

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    // MARK: - 计算属性

    /// 格式化后的时长文本
    var durationText: String {
        let totalMinutes = Int(duration) / 60
        if totalMinutes >= 60 {
            let hours = totalMinutes / 60
            let mins = totalMinutes % 60
            if mins > 0 { return L10n.shared.小时分钟(hours, mins) }
            return L10n.shared.小时(hours)
        }
        return L10n.shared.分钟(totalMinutes)
    }
    
    /// 时间范围文本
    var timeRangeText: String {
        let start = Self.timeFormatter.string(from: startTime)
        if let end = endTime { return "\(start) - \(Self.timeFormatter.string(from: end))" }
        return start
    }
}

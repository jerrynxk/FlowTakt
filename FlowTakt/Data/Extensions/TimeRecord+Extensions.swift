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
    ///
    /// 2026-11-19 审查：不足 1 分钟原本一律显示「0分钟」—— 短记录（30 秒、误触 2 秒）
    /// 在列表里全变成无意义的「0分钟」。改为按秒显示，时长真实可读。
    var durationText: String {
        let totalSeconds = Int(duration)
        let totalMinutes = totalSeconds / 60
        if totalMinutes >= 60 {
            let hours = totalMinutes / 60
            let mins = totalMinutes % 60
            if mins > 0 { return L10n.shared.小时分钟(hours, mins) }
            return L10n.shared.小时(hours)
        }
        if totalMinutes > 0 { return L10n.shared.分钟(totalMinutes) }
        return L10n.shared.秒数(max(0, totalSeconds))
    }
    
    /// 时间范围文本
    var timeRangeText: String {
        let start = Self.timeFormatter.string(from: startTime)
        if let end = endTime { return "\(start) - \(Self.timeFormatter.string(from: end))" }
        return start
    }
}

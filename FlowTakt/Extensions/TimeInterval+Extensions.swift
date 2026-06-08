import Foundation

// MARK: - TimeInterval 扩展

extension TimeInterval {
    /// 格式化为 "X小时X分钟" 或 "X分钟"
    var formattedDuration: String {
        let totalMinutes = Int(self) / 60
        if totalMinutes >= 60 {
            let hours = totalMinutes / 60
            let minutes = totalMinutes % 60
            if minutes > 0 {
                return "\(hours)小时\(minutes)分钟"
            }
            return "\(hours)小时"
        }
        return "\(totalMinutes)分钟"
    }

    /// 格式化为简短时长 "XX:XX"
    var mmssString: String {
        let totalSeconds = Int(self)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

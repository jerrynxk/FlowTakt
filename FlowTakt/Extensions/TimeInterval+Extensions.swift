import Foundation

// MARK: - TimeInterval 扩展

extension TimeInterval {
    /// 格式化为中文 "X小时X分钟" 或英文 "Xh Xm"
    var formattedDuration: String {
        let totalMinutes = Int(self) / 60

        if totalMinutes >= 60 {
            let hours = totalMinutes / 60
            let minutes = totalMinutes % 60
            if minutes > 0 {
                return L10n.shared.小时分钟(hours, minutes)
            }
            return L10n.shared.小时(hours)
        }
        return L10n.shared.分钟(totalMinutes)
    }

    /// 格式化为简短时长 "XX:XX"
    var mmssString: String {
        let totalSeconds = Int(self)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

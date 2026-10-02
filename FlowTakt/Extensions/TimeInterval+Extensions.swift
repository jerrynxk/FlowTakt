import Foundation

// MARK: - TimeInterval 扩展

extension TimeInterval {
    /// 格式化为中文 "X小时X分钟" 或英文 "Xh Xm"
    /// 审查修复（2026-08-12）：<60 秒不再显示"0分钟"，按 1 分钟兜底
    var formattedDuration: String {
        let totalMinutes = Int(self) / 60

        // 非零但不足 1 分钟的时长显示为 1 分钟
        if self > 0 && totalMinutes < 1 {
            return L10n.shared.分钟(1)
        }

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
}

import Foundation
import CoreData

// MARK: - FocusSession 扩展方法

extension FocusSession {
    /// 实际专注时长（格式化文本），根据 locale 显示中文或英文格式
    var durationText: String {
        let duration = actualDuration > 0 ? actualDuration : plannedDuration
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        if seconds > 0 {
            return L10n.shared.分秒(minutes, seconds)
        }
        return L10n.shared.分钟(minutes)
    }

    /// 是否已完成
    var isCompleted: Bool {
        status == SessionStatus.completed.rawValue
    }

    /// 是否进行中
    var isRunning: Bool {
        status == SessionStatus.running.rawValue
    }
}

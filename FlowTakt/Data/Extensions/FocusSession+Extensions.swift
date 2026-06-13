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

    /// 专注阶段显示名称，支持国际化
    var phaseDisplayName: String {
        switch phase {
        case FocusPhase.focus.rawValue: return L10n.shared.focus
        case FocusPhase.shortBreak.rawValue: return L10n.shared.短休息
        case FocusPhase.longBreak.rawValue: return L10n.shared.长休息
        default: return phase
        }
    }

    /// 状态显示名称，支持国际化
    var statusDisplayName: String {
        switch status {
        case SessionStatus.running.rawValue: return L10n.shared.进行中
        case SessionStatus.completed.rawValue: return L10n.shared.已完成
        case SessionStatus.interrupted.rawValue: return L10n.shared.已中断
        case SessionStatus.abandoned.rawValue: return L10n.shared.已放弃
        default: return status
        }
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

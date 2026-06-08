import Foundation
import CoreData

// MARK: - FocusSession 扩展方法

extension FocusSession {
    /// 实际专注时长（格式化文本）
    var durationText: String {
        let duration = actualDuration > 0 ? actualDuration : plannedDuration
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        if seconds > 0 {
            return "\(minutes)分\(seconds)秒"
        }
        return "\(minutes)分钟"
    }

    /// 专注阶段显示名称
    var phaseDisplayName: String {
        switch phase {
        case FocusPhase.focus.rawValue: return "专注"
        case FocusPhase.shortBreak.rawValue: return "短休息"
        case FocusPhase.longBreak.rawValue: return "长休息"
        default: return phase
        }
    }

    /// 状态显示名称
    var statusDisplayName: String {
        switch status {
        case SessionStatus.running.rawValue: return "进行中"
        case SessionStatus.completed.rawValue: return "已完成"
        case SessionStatus.interrupted.rawValue: return "已中断"
        case SessionStatus.abandoned.rawValue: return "已放弃"
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

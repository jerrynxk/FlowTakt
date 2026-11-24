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

    /// 是否已完成（唯一判据：正常走完计划时长）
    var isCompleted: Bool {
        status == SessionStatus.completed.rawValue
    }

    /// 是否提前结束（用户主动停止但保留了净专注时长）
    var isEarlyCompleted: Bool {
        status == SessionStatus.earlyCompleted.rawValue
    }

    /// 是否计入专注时长总和（completed 与 earlyCompleted 均计入；
    /// interrupted / abandoned / running / paused 不计入）。
    /// 判据收口在此处，时长统计不得在调用点各自拼 predicate。
    var countsTowardDuration: Bool {
        isCompleted || isEarlyCompleted
    }

    /// 是否为"未完成计划的中断"（abandoned + earlyCompleted）。
    /// 判据收口在此处：中断洞察、原因分析统一使用，避免提前结束后原因丢失。
    var isInterruption: Bool {
        status == SessionStatus.abandoned.rawValue || isEarlyCompleted
    }

    /// 是否进行中
    var isRunning: Bool {
        status == SessionStatus.running.rawValue
    }

    /// 统计归属标签（用户反馈 2026-11-19「按标签分别统计耗时」）。
    ///
    /// 判据顺序：会话自身标签 → 所属任务的首个标签（按名称稳定排序）。
    /// 采用**单归属**而非多标签均分：均分会让「各标签时长之和」不再等于总时长，
    /// 用户无法核对；单归属保证守恒，且同一任务每次统计落入同一标签。
    var resolvedTag: Tag? {
        if let own = tag { return own }
        guard let taskTags = task?.tags, !taskTags.isEmpty else { return nil }
        return taskTags.sorted { $0.name < $1.name }.first
    }
}

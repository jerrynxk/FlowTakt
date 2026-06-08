import Foundation
import CoreData

// MARK: - Task 扩展方法

extension Task {
    /// 格式化后的优先级文本
    var priorityText: String {
        switch priority {
        case 3: return "高"
        case 2: return "中"
        case 1: return "低"
        default: return "未知"
        }
    }

    /// 当前番茄钟进度
    var pomodoroProgress: Double {
        guard estimatedPomodoros > 0 else { return 0 }
        return Double(completedPomodoros) / Double(estimatedPomodoros)
    }

    /// 是否已完成
    var isCompleted: Bool {
        status == TaskStatus.completed.rawValue
    }

    /// 是否已归档
    var isArchived: Bool {
        status == TaskStatus.archived.rawValue
    }

    /// 是否有子任务
    var hasSubTasks: Bool {
        subTasks.count > 0
    }

    /// 子任务完成率
    var subTaskCompletionRate: Double {
        guard subTasks.count > 0 else { return 0 }
        let completed = subTasks.filter { $0.status == TaskStatus.completed.rawValue }.count
        return Double(completed) / Double(subTasks.count)
    }

    /// 是否是子任务
    var isSubTask: Bool {
        parentTask != nil
    }

    /// 重复规则描述
    var recurrenceDescription: String? {
        guard isRecurring, let rule = recurrenceRule else { return nil }
        switch rule {
        case "daily": return "每天"
        case "weekly": return "每周"
        case "biweekly": return "每两周"
        case "monthly": return "每月"
        case "yearly": return "每年"
        case "weekday": return "工作日"
        default: return rule
        }
    }
}

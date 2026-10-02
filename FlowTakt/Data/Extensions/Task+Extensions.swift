import Foundation
import CoreData

// MARK: - Task 扩展方法

extension Task {
    /// 当前番茄钟进度
    var pomodoroProgress: Double {
        guard estimatedPomodoros > 0 else { return 0 }
        return Double(completedPomodoros) / Double(estimatedPomodoros)
    }

    /// 是否已完成
    var isCompleted: Bool {
        TaskStatus(rawValue: status) == .completed
    }

    /// 是否已归档
    var isArchived: Bool {
        TaskStatus(rawValue: status) == .archived
    }
}

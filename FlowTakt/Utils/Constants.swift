import Foundation
import SwiftUI

// MARK: - 全局枚举定义

/// 专注阶段：专注 / 短休息 / 长休息
enum FocusPhase: String, Codable, CaseIterable {
    case focus
    case shortBreak
    case longBreak
}

/// 专注会话状态
enum SessionStatus: String, Codable {
    case running
    case completed
    case interrupted
    case abandoned
}

/// 任务状态
enum TaskStatus: String, Codable, CaseIterable {
    case active
    case completed
    case archived
}

/// 日期范围筛选
enum DateRange: Equatable {
    case today
    case week
    case month
    case year
    case custom(start: Date, end: Date)
}

/// 成就分类
enum AchievementCategory: String, Codable, CaseIterable {
    case streak      // 连续成就
    case total       // 累积成就
    case speed       // 速度成就
    case special     // 特殊成就
}

/// 应用统一错误类型
enum AppError: LocalizedError {
    case coreDataSaveFailed(Error)
    case cloudKitSyncFailed(Error)
    case notificationDenied
    case timerInvalid
    case sessionNotFound
    case taskNotFound

    var errorDescription: String? {
        switch self {
        case .coreDataSaveFailed(let error):
            return "数据保存失败：\(error.localizedDescription)"
        case .cloudKitSyncFailed(let error):
            return "iCloud 同步失败：\(error.localizedDescription)"
        case .notificationDenied:
            return "通知权限被拒绝，请在设置中开启"
        case .timerInvalid:
            return "计时器状态异常"
        case .sessionNotFound:
            return "未找到专注会话"
        case .taskNotFound:
            return "未找到任务"
        }
    }
}

// MARK: - 全局常量

struct AppConstants {
    /// 默认番茄钟时长（秒）
    static let defaultFocusDuration: TimeInterval = 25 * 60
    /// 默认短休息时长（秒）
    static let defaultShortBreakDuration: TimeInterval = 5 * 60
    /// 默认长休息时长（秒）
    static let defaultLongBreakDuration: TimeInterval = 15 * 60
    /// 长休息触发轮次（每完成 N 个番茄钟后）
    static let longBreakAfterRounds: Int = 4
    /// 完成一个番茄钟获得积分
    static let pointsPerCompletedPomodoro: Int = 10
    /// 中断/放弃扣除积分
    static let pointsPenaltyPerInterrupt: Int = -5

    /// 成就：完成番茄钟数阈值
    static let achievements: [(identifier: String, title: String, description: String, iconName: String, category: AchievementCategory, threshold: Int)] = [
        ("first_pomodoro", "初次专注", "完成你的第一个番茄钟", "star.fill", .total, 1),
        ("pomodoros_10", "专注新手", "累计完成 10 个番茄钟", "10.square.fill", .total, 10),
        ("pomodoros_50", "专注达人", "累计完成 50 个番茄钟", "50.square.fill", .total, 50),
        ("pomodoros_100", "专注大师", "累计完成 100 个番茄钟", "100.square.fill", .total, 100),
        ("streak_3", "初现坚持", "连续 3 天使用番茄钟", "3.circle.fill", .streak, 3),
        ("streak_7", "一周坚持", "连续 7 天使用番茄钟", "7.circle.fill", .streak, 7),
        ("streak_30", "月度坚持", "连续 30 天使用番茄钟", "30.circle.fill", .streak, 30),
        ("points_100", "积分新星", "累计获得 100 积分", "100.circle.fill", .total, 100),
        ("points_500", "积分达人", "累计获得 500 积分", "500.circle.fill", .total, 500),
        ("points_1000", "积分大师", "累计获得 1000 积分", "1000.circle.fill", .total, 1000),
    ]

    /// 应用组 ID（用于共享 UserDefaults 和 CoreData）
    static let appGroupIdentifier = "group.com.flowtakt"
    /// CloudKit 容器标识符
    static let cloudKitContainerIdentifier = "iCloud.com.flowtakt"

    /// 默认专注时长选项（分钟）
    static let focusDurationOptions: [TimeInterval] = [15, 25, 30, 45, 60].map { TimeInterval($0 * 60) }
    /// 默认短休息时长选项（分钟）
    static let shortBreakOptions: [TimeInterval] = [3, 5, 10].map { TimeInterval($0 * 60) }
    /// 默认长休息时长选项（分钟）
    static let longBreakOptions: [TimeInterval] = [10, 15, 20, 30].map { TimeInterval($0 * 60) }
}

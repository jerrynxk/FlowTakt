import Foundation
import UIKit   // HapticManager 触觉反馈（UINotificationFeedbackGenerator.FeedbackType）
@preconcurrency import CoreData

// MARK: - AchievementService 协议

protocol AchievementServiceProtocol: AnyObject {
    func checkAndUnlockAchievements()
    func fetchAllAchievements() -> [Achievement]
    func getTotalPoints() -> Int
    func getTodaysPoints() -> Int
    func getUnlockedAchievementCount() -> Int
}

// MARK: - 成就服务实现

final class AchievementService: AchievementServiceProtocol {
    private let persistenceController: PersistenceController

    /// Streak 计算最大迭代上限（防止死循环）
    private static let maxStreakIterations = 10000

    /// 错误回调：供 ViewModel 层监听 Service 内部错误
    var onError: ((Error) -> Void)?

    private var viewContext: NSManagedObjectContext {
        persistenceController.viewContext
    }

    init(persistenceController: PersistenceController) {
        self.persistenceController = persistenceController
    }

    func checkAndUnlockAchievements() {
        // 单次全量拉取已完成会话，内存计算 total / points / streak，避免三次全表扫描
        let completedSessions = fetchCompletedSessions()
        let totalCompleted = completedSessions.count
        let totalPoints = completedSessions.reduce(0) { $0 + Int($1.earnedPoints) }
        let currentStreak = Self.computeStreak(from: completedSessions)

        let allAchievements = fetchAllAchievements()

        // 触觉反馈：本次是否有新解锁（循环后统一触发一次，避免多个成就连震）
        var hasNewlyUnlocked = false

        for achievement in allAchievements where !achievement.isUnlocked {
            let shouldUnlock: Bool
            switch achievement.identifier {
            case _ where achievement.identifier.hasPrefix("first_pomodoro"):
                shouldUnlock = totalCompleted >= 1
            case _ where achievement.identifier.hasPrefix("pomodoros_"):
                shouldUnlock = totalCompleted >= Int(achievement.thresholdValue)
            case _ where achievement.identifier.hasPrefix("streak_"):
                shouldUnlock = currentStreak >= Int(achievement.thresholdValue)
            case _ where achievement.identifier.hasPrefix("points_"):
                shouldUnlock = totalPoints >= Int(achievement.thresholdValue)
            default:
                shouldUnlock = false
            }

            if shouldUnlock {
                achievement.isUnlocked = true
                achievement.unlockedAt = Date()
                hasNewlyUnlocked = true
            }
        }

        if hasNewlyUnlocked {
            // 触觉反馈：成就解锁（成功通知）
            HapticManager.shared.notificationFeedback(type: .success)
        }

        persistenceController.save()
    }

    func fetchAllAchievements() -> [Achievement] {
        let request = Achievement.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Achievement.thresholdValue, ascending: true)]

        do {
            let existing = try viewContext.fetch(request)
            if existing.isEmpty {
                return createDefaultAchievements()
            }
            return existing
        } catch {
            print("获取成就列表失败：\(error.localizedDescription)")
            onError?(error)
            return []
        }
    }

    func getTotalPoints() -> Int {
        let request = FocusSession.fetchRequest()
        // 审查修复（2026-08-12 第二轮）：与 fetchCompletedSessions 对齐，只统计专注阶段积分；
        // 休息阶段完成的 FocusSession.earnedPoints 可能非零，需排除
        request.predicate = NSPredicate(
            format: "status == %@ AND phase == %@",
            SessionStatus.completed.rawValue,
            FocusPhase.focus.rawValue
        )

        do {
            let sessions = try viewContext.fetch(request)
            return sessions.reduce(0) { $0 + Int($1.earnedPoints) }
        } catch {
            print("获取总积分失败：\(error.localizedDescription)")
            onError?(error)
            return 0
        }
    }

    func getTodaysPoints() -> Int {
        let request = FocusSession.fetchRequest()
        let todayStart = Date().startOfDay
        let todayEnd = Date().endOfDay
        // 半开区间 [todayStart, todayEnd)
        // 审查修复（2026-08-12 第二轮）：只统计专注阶段今日积分
        request.predicate = NSPredicate(
            format: "status == %@ AND startTime >= %@ AND startTime < %@ AND phase == %@",
            SessionStatus.completed.rawValue,
            todayStart as NSDate,
            todayEnd as NSDate,
            FocusPhase.focus.rawValue
        )

        do {
            let sessions = try viewContext.fetch(request)
            return sessions.reduce(0) { $0 + Int($1.earnedPoints) }
        } catch {
            print("获取今日积分失败：\(error.localizedDescription)")
            onError?(error)
            return 0
        }
    }

    func getUnlockedAchievementCount() -> Int {
        let request = Achievement.fetchRequest()
        request.predicate = NSPredicate(format: "isUnlocked == YES")

        do {
            return try viewContext.fetch(request).count
        } catch {
            print("获取已解锁成就数失败：\(error.localizedDescription)")
            onError?(error)
            return 0
        }
    }

    // MARK: - 私有方法

    private func createDefaultAchievements() -> [Achievement] {
        var achievements: [Achievement] = []
        for info in AppConstants.achievements {
            let achievement = Achievement(context: viewContext)
            achievement.id = UUID()
            achievement.identifier = info.identifier
            achievement.title = info.title
            achievement.descriptionText = info.description
            achievement.iconName = info.iconName
            achievement.category = info.category.rawValue
            achievement.thresholdValue = Int16(info.threshold)
            achievement.isUnlocked = false
            achievement.createdAt = Date()
            achievements.append(achievement)
        }
        persistenceController.save()
        return achievements
    }

    private func fetchCompletedSessions() -> [FocusSession] {
        let request = FocusSession.fetchRequest()
        // 审查修复（2026-08-12）：只统计专注阶段完成会话，短/长休息完成不算番茄数，
        // 否则完成休息也能解锁 first_pomodoro/pomodoros_* 成就
        request.predicate = NSPredicate(
            format: "status == %@ AND phase == %@",
            SessionStatus.completed.rawValue,
            FocusPhase.focus.rawValue
        )
        do {
            return try viewContext.fetch(request)
        } catch {
            print("获取已完成会话失败：\(error.localizedDescription)")
            onError?(error)
            return []
        }
    }

    /// 计算连续打卡天数：从最近一次完成会话向前倒推，逐日检查。
    /// 优化：按天分组后再判断，避免 O(streak×n) 的双重循环。
    /// 语义：今天未打卡不中断昨天的连续记录（从昨天开始倒推）。
    private static func computeStreak(from sessions: [FocusSession]) -> Int {
        guard !sessions.isEmpty else { return 0 }

        let calendar = Calendar.current
        // 按天分组：[startOfDay: 非空]
        let daySet = Set(sessions.map { calendar.startOfDay(for: $0.startTime) })

        let today = calendar.startOfDay(for: Date())
        var streak = 0
        var currentDate: Date
        if daySet.contains(today) {
            currentDate = today
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
                  daySet.contains(yesterday) {
            // 今天还没打卡，但昨天有 → streak 从昨天开始计算
            currentDate = yesterday
        } else {
            return 0
        }

        while streak < maxStreakIterations {
            if daySet.contains(currentDate) {
                streak += 1
                guard let previousDay = calendar.date(byAdding: .day, value: -1, to: currentDate) else {
                    break
                }
                currentDate = previousDay
            } else {
                break
            }
        }
        return streak
    }
}

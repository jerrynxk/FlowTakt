import Foundation
import CoreData

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

    init(persistenceController: PersistenceController, focusService: FocusServiceProtocol) {
        self.persistenceController = persistenceController
    }

    func checkAndUnlockAchievements() {
        viewContext.performAndWait {
            let completedSessions = fetchCompletedSessions()
            let totalCompleted = completedSessions.count
            let totalPoints = getTotalPoints()

            let allAchievements = fetchAllAchievements()

            for achievement in allAchievements where !achievement.isUnlocked {
                let shouldUnlock: Bool
                switch achievement.identifier {
                case _ where achievement.identifier.hasPrefix("first_pomodoro"):
                    shouldUnlock = totalCompleted >= 1
                case _ where achievement.identifier.hasPrefix("pomodoros_"):
                    let threshold = Int(achievement.thresholdValue)
                    shouldUnlock = totalCompleted >= threshold
                case _ where achievement.identifier.hasPrefix("streak_"):
                    let threshold = Int(achievement.thresholdValue)
                    shouldUnlock = getCurrentStreak() >= threshold
                case _ where achievement.identifier.hasPrefix("points_"):
                    let threshold = Int(achievement.thresholdValue)
                    shouldUnlock = totalPoints >= threshold
                default:
                    shouldUnlock = false
                }

                if shouldUnlock {
                    achievement.isUnlocked = true
                    achievement.unlockedAt = Date()
                }
            }

            persistenceController.save()
        }
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
        request.predicate = NSPredicate(format: "status == %@", SessionStatus.completed.rawValue)

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
        request.predicate = NSPredicate(
            format: "status == %@ AND startTime >= %@ AND startTime <= %@",
            SessionStatus.completed.rawValue,
            todayStart as NSDate,
            todayEnd as NSDate
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
        viewContext.performAndWait {
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
        }
        return achievements
    }

    private func fetchCompletedSessions() -> [FocusSession] {
        let request = FocusSession.fetchRequest()
        request.predicate = NSPredicate(format: "status == %@", SessionStatus.completed.rawValue)
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
    private func getCurrentStreak() -> Int {
        let request = FocusSession.fetchRequest()
        request.predicate = NSPredicate(format: "status == %@", SessionStatus.completed.rawValue)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \FocusSession.startTime, ascending: false)]

        do {
            let sessions = try viewContext.fetch(request)
            guard !sessions.isEmpty else { return 0 }

            let calendar = Calendar.current
            // 按天分组：[startOfDay: 非空]
            var daySet = Set<Date>()
            for session in sessions {
                daySet.insert(calendar.startOfDay(for: session.startTime))
            }

            // 如果今天没有任何会话，streak 从昨天开始倒推（今天未打卡不中断昨天的连续记录）
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

            let maxIterations = Self.maxStreakIterations
            while streak < maxIterations {
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
        } catch {
            print("获取连续天数失败：\(error.localizedDescription)")
            onError?(error)
            return 0
        }
    }
}

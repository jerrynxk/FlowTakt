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
    private weak var focusService: FocusServiceProtocol?

    private var viewContext: NSManagedObjectContext {
        persistenceController.viewContext
    }

    init(persistenceController: PersistenceController, focusService: FocusServiceProtocol) {
        self.persistenceController = persistenceController
        self.focusService = focusService
    }

    func checkAndUnlockAchievements() {
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

    func fetchAllAchievements() -> [Achievement] {
        // 如果还没有成就记录，先初始化默认成就列表
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
            return 0
        }
    }

    func getUnlockedAchievementCount() -> Int {
        let request = Achievement.fetchRequest()
        request.predicate = NSPredicate(format: "isUnlocked == YES")
        do {
            return try viewContext.fetch(request).count
        } catch {
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
        request.predicate = NSPredicate(format: "status == %@", SessionStatus.completed.rawValue)
        do {
            return try viewContext.fetch(request)
        } catch {
            return []
        }
    }

    private func getCurrentStreak() -> Int {
        let request = FocusSession.fetchRequest()
        request.predicate = NSPredicate(format: "status == %@", SessionStatus.completed.rawValue)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \FocusSession.startTime, ascending: false)]

        do {
            let sessions = try viewContext.fetch(request)
            guard !sessions.isEmpty else { return 0 }

            let calendar = Calendar.current
            var streak = 0
            guard let latestSession = sessions.first else { return 0 }
            var currentDate = calendar.startOfDay(for: latestSession.startTime)

            while true {
                let sessionsOnDate = sessions.filter {
                    calendar.isDate($0.startTime, inSameDayAs: currentDate)
                }
                if sessionsOnDate.isEmpty {
                    break
                }
                streak += 1
                guard let previousDay = calendar.date(byAdding: .day, value: -1, to: currentDate) else {
                    break
                }
                currentDate = previousDay
            }
            return streak
        } catch {
            return 0
        }
    }
}

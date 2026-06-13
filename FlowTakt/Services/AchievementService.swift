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

    /// 错误回调：供 ViewModel 层监听 Service 内部错误
    var onError: ((Error) -> Void)?

    private var viewContext: NSManagedObjectContext {
        persistenceController.viewContext
    }

    private lazy var backgroundContext: NSManagedObjectContext = {
        let ctx = persistenceController.newBackgroundContext()
        ctx.automaticallyMergesChangesFromParent = true
        return ctx
    }()

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

        var total: Int = 0
        backgroundContext.performAndWait {
            do {
                let sessions = try backgroundContext.fetch(request)
                total = sessions.reduce(0) { $0 + Int($1.earnedPoints) }
            } catch {
                print("获取总积分失败：\(error.localizedDescription)")
                DispatchQueue.main.async { [weak self] in
                    self?.onError?(error)
                }
            }
        }
        return total
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

        var total: Int = 0
        backgroundContext.performAndWait {
            do {
                let sessions = try backgroundContext.fetch(request)
                total = sessions.reduce(0) { $0 + Int($1.earnedPoints) }
            } catch {
                print("获取今日积分失败：\(error.localizedDescription)")
                DispatchQueue.main.async { [weak self] in
                    self?.onError?(error)
                }
            }
        }
        return total
    }

    func getUnlockedAchievementCount() -> Int {
        let request = Achievement.fetchRequest()
        request.predicate = NSPredicate(format: "isUnlocked == YES")

        var count: Int = 0
        backgroundContext.performAndWait {
            do {
                count = try backgroundContext.fetch(request).count
            } catch {
                print("获取已解锁成就数失败：\(error.localizedDescription)")
                DispatchQueue.main.async { [weak self] in
                    self?.onError?(error)
                }
            }
        }
        return count
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
            print("获取已完成会话失败：\(error.localizedDescription)")
            onError?(error)
            return []
        }
    }

    private func getCurrentStreak() -> Int {
        let request = FocusSession.fetchRequest()
        request.predicate = NSPredicate(format: "status == %@", SessionStatus.completed.rawValue)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \FocusSession.startTime, ascending: false)]

        var streak: Int = 0
        backgroundContext.performAndWait {
            do {
                let sessions = try backgroundContext.fetch(request)
                guard !sessions.isEmpty else { return }

                let calendar = Calendar.current
                let maxIterations = 10000
                guard let latestSession = sessions.first else { return }
                var currentDate = calendar.startOfDay(for: latestSession.startTime)

                while streak < maxIterations {
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
            } catch {
                print("获取连续天数失败：\(error.localizedDescription)")
                DispatchQueue.main.async { [weak self] in
                    self?.onError?(error)
                }
            }
        }
        return streak
    }
}

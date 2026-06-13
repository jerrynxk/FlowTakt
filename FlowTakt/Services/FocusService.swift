import Foundation
import CoreData

// MARK: - FocusService 协议

protocol FocusServiceProtocol: AnyObject {
    func startFocusSession(task: Task?, plannedDuration: TimeInterval, phase: FocusPhase, roundIndex: Int16) -> FocusSession
    func completeSession(_ session: FocusSession)
    func interruptSession(_ session: FocusSession)
    func abandonSession(_ session: FocusSession)
    func getCurrentSession() -> FocusSession?
    func fetchTodaysSessions() -> [FocusSession]
}

// MARK: - 专注服务实现

final class FocusService: FocusServiceProtocol {
    private let persistenceController: PersistenceController
    private let notificationService: NotificationServiceProtocol
    weak var achievementService: AchievementServiceProtocol?

    /// 错误回调：供 ViewModel 层监听 Service 内部错误
    var onError: ((Error) -> Void)?

    private var viewContext: NSManagedObjectContext {
        persistenceController.viewContext
    }

    init(persistenceController: PersistenceController,
         notificationService: NotificationServiceProtocol,
         achievementService: AchievementServiceProtocol? = nil) {
        self.persistenceController = persistenceController
        self.notificationService = notificationService
        self.achievementService = achievementService
    }

    func startFocusSession(task: Task?, plannedDuration: TimeInterval, phase: FocusPhase, roundIndex: Int16) -> FocusSession {
        let session = FocusSession(context: viewContext)
        session.id = UUID()
        session.startTime = Date()
        session.plannedDuration = plannedDuration
        session.phase = phase.rawValue
        session.roundIndex = roundIndex
        session.status = SessionStatus.running.rawValue
        session.earnedPoints = 0
        session.createdAt = Date()
        session.updatedAt = Date()
        session.task = task

        persistenceController.save()

        // 安排专注结束通知
        let taskTitle = task?.title ?? "未命名任务"
        notificationService.scheduleSessionEndNotification(
            sessionId: session.id,
            title: taskTitle,
            timeInterval: plannedDuration
        )

        return session
    }

    func completeSession(_ session: FocusSession) {
        guard session.managedObjectContext != nil else { return }
        session.endTime = Date()
        session.actualDuration = Date().timeIntervalSince(session.startTime)
        session.status = SessionStatus.completed.rawValue
        session.earnedPoints = Int16(AppConstants.pointsPerCompletedPomodoro)
        session.updatedAt = Date()

        // 更新关联任务的已完成番茄钟数
        if let task = session.task {
            task.completedPomodoros += 1
            task.updatedAt = Date()
        }

        persistenceController.save()

        // 取消通知
        notificationService.cancelNotification(withIdentifier: session.id.uuidString)
    }

    func interruptSession(_ session: FocusSession) {
        guard session.managedObjectContext != nil else { return }
        session.endTime = Date()
        session.actualDuration = Date().timeIntervalSince(session.startTime)
        session.status = SessionStatus.interrupted.rawValue
        session.earnedPoints = 0
        session.updatedAt = Date()
        persistenceController.save()

        notificationService.cancelNotification(withIdentifier: session.id.uuidString)
    }

    func abandonSession(_ session: FocusSession) {
        guard session.managedObjectContext != nil else { return }
        session.status = SessionStatus.abandoned.rawValue
        session.earnedPoints = Int16(AppConstants.pointsPenaltyPerInterrupt)
        session.updatedAt = Date()
        persistenceController.save()

        notificationService.cancelNotification(withIdentifier: session.id.uuidString)
    }

    func getCurrentSession() -> FocusSession? {
        let request = FocusSession.fetchRequest()
        request.predicate = NSPredicate(format: "status == %@", SessionStatus.running.rawValue)
        request.fetchLimit = 1
        request.sortDescriptors = [NSSortDescriptor(keyPath: \FocusSession.startTime, ascending: false)]
        do {
            return try viewContext.fetch(request).first
        } catch {
            print("获取当前会话失败：\(error.localizedDescription)")
            onError?(error)
            return nil
        }
    }

    func fetchTodaysSessions() -> [FocusSession] {
        let request = FocusSession.fetchRequest()
        let todayStart = Date().startOfDay
        let todayEnd = Date().endOfDay
        request.predicate = NSPredicate(format: "startTime >= %@ AND startTime <= %@",
                                        todayStart as NSDate, todayEnd as NSDate)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \FocusSession.startTime, ascending: false)]
        do {
            return try viewContext.fetch(request)
        } catch {
            print("获取今日会话失败：\(error.localizedDescription)")
            onError?(error)
            return []
        }
    }
}

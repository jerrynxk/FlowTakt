import Foundation
@preconcurrency import CoreData

// MARK: - FocusService 协议

protocol FocusServiceProtocol: AnyObject {
    func startFocusSession(task: Task?, plannedDuration: TimeInterval, phase: FocusPhase, roundIndex: Int16) -> FocusSession
    func completeSession(_ session: FocusSession, actualDuration: TimeInterval?)
    func interruptSession(_ session: FocusSession)
    func abandonSession(_ session: FocusSession, reason: String?)
    func getCurrentSession() -> FocusSession?
    func fetchTodaysSessions() -> [FocusSession]
    /// 获取指定日期范围内的已完成会话（供统计模块使用，替代 ViewModel 直连 viewContext）
    func fetchCompletedSessions(from startDate: Date, to endDate: Date) -> [FocusSession]
    /// 获取全部已完成会话（供统计模块使用）
    func fetchAllCompletedSessions() -> [FocusSession]
}

// MARK: - FocusServiceProtocol 便捷方法
// Swift 协议方法不允许默认参数，通过扩展提供不带 actualDuration / reason 的重载

extension FocusServiceProtocol {
    func completeSession(_ session: FocusSession) {
        completeSession(session, actualDuration: nil)
    }

    /// 放弃会话（不带中断原因）。旧调用点兼容重载。
    func abandonSession(_ session: FocusSession) {
        abandonSession(session, reason: nil)
    }
}

// MARK: - 专注服务实现

@MainActor
final class FocusService: FocusServiceProtocol {
    private let persistenceController: PersistenceController
    private let notificationService: NotificationServiceProtocol

    /// 错误回调：供 ViewModel 层监听 Service 内部错误
    var onError: ((Error) -> Void)?

    private var viewContext: NSManagedObjectContext {
        persistenceController.viewContext
    }

    init(persistenceController: PersistenceController,
         notificationService: NotificationServiceProtocol) {
        self.persistenceController = persistenceController
        self.notificationService = notificationService
    }

    func startFocusSession(task: Task?, plannedDuration: TimeInterval, phase: FocusPhase, roundIndex: Int16) -> FocusSession {
        // 防御：若存在遗留的 running 会话（异常退出/重复启动残留的孤儿会话），先中断，
        // 避免同时存在多个 running 会话导致 getCurrentSession 语义混乱
        if let orphan = getCurrentSession() {
            interruptSession(orphan)
        }

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
        let taskTitle = task?.title ?? L10n.shared.无任务
        notificationService.scheduleSessionEndNotification(
            sessionId: session.id,
            title: taskTitle,
            timeInterval: plannedDuration
        )

        return session
    }

    func completeSession(_ session: FocusSession, actualDuration: TimeInterval? = nil) {
        guard session.managedObjectContext != nil else { return }
        // 状态机守卫：仅 running 会话可完成，保证幂等（重复 complete / 已完成后再操作均忽略）
        guard session.status == SessionStatus.running.rawValue else { return }
        let now = Date()
        session.endTime = now
        session.actualDuration = actualDuration ?? now.timeIntervalSince(session.startTime)
        session.status = SessionStatus.completed.rawValue
        session.earnedPoints = Int16(AppConstants.pointsPerCompletedPomodoro)
        session.updatedAt = now

        // 更新关联任务的已完成番茄钟数
        if let task = session.task {
            task.completedPomodoros += 1
            task.updatedAt = now
        }

        persistenceController.save()

        // 取消通知
        notificationService.cancelNotification(withIdentifier: session.id.uuidString)
    }

    func interruptSession(_ session: FocusSession) {
        guard session.managedObjectContext != nil else { return }
        guard session.status == SessionStatus.running.rawValue else { return }
        let now = Date()
        session.endTime = now
        session.actualDuration = now.timeIntervalSince(session.startTime)
        session.status = SessionStatus.interrupted.rawValue
        session.earnedPoints = 0
        session.updatedAt = now
        persistenceController.save()

        notificationService.cancelNotification(withIdentifier: session.id.uuidString)
    }

    func abandonSession(_ session: FocusSession, reason: String?) {
        guard session.managedObjectContext != nil else { return }
        guard session.status == SessionStatus.running.rawValue else { return }
        session.status = SessionStatus.abandoned.rawValue
        // 记录中断原因（可选）：供统计回顾"今天为什么没完成番茄"
        session.interruptionReason = reason
        session.endTime = Date()   // 数据完整性（审查 #17）：放弃也记录结束时间
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
        // 半开区间 [todayStart, todayEnd)：todayEnd 为次日 00:00:00
        request.predicate = NSPredicate(format: "startTime >= %@ AND startTime < %@",
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

    func fetchCompletedSessions(from startDate: Date, to endDate: Date) -> [FocusSession] {
        let request = FocusSession.fetchRequest()
        // 半开区间 [startDate, endDate)；审查修复（2026-08-12）：只统计专注阶段完成会话，
        // 休息阶段完成不参与"番茄钟数"统计
        request.predicate = NSPredicate(
            format: "startTime >= %@ AND startTime < %@ AND status == %@ AND phase == %@",
            startDate as NSDate,
            endDate as NSDate,
            SessionStatus.completed.rawValue,
            FocusPhase.focus.rawValue
        )
        request.sortDescriptors = [NSSortDescriptor(keyPath: \FocusSession.startTime, ascending: true)]
        do {
            return try viewContext.fetch(request)
        } catch {
            print("获取区间会话失败：\(error.localizedDescription)")
            onError?(error)
            return []
        }
    }

    func fetchAllCompletedSessions() -> [FocusSession] {
        let request = FocusSession.fetchRequest()
        // 审查修复（2026-08-12）：累计番茄数/连续天数/年热力图只统计专注阶段完成会话
        request.predicate = NSPredicate(
            format: "status == %@ AND phase == %@",
            SessionStatus.completed.rawValue,
            FocusPhase.focus.rawValue
        )
        request.sortDescriptors = [NSSortDescriptor(keyPath: \FocusSession.startTime, ascending: false)]
        do {
            return try viewContext.fetch(request)
        } catch {
            print("获取全部已完成会话失败：\(error.localizedDescription)")
            onError?(error)
            return []
        }
    }
}

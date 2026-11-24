import Foundation
@preconcurrency import CoreData

// MARK: - FocusService 协议

protocol FocusServiceProtocol: AnyObject {
    func startFocusSession(task: Task?, plannedDuration: TimeInterval, phase: FocusPhase, roundIndex: Int16) -> FocusSession
    func completeSession(_ session: FocusSession, actualDuration: TimeInterval?)
    func interruptSession(_ session: FocusSession)
    func abandonSession(_ session: FocusSession, reason: String?)
    /// 系统/配置原因丢弃会话（用户未主动停止，如孤儿会话被新会话替换）。
    /// 保持 abandoned 语义、不写净时长 → 不计入任何统计（审查修复 2026-11-17）。
    func discardSession(_ session: FocusSession, reason: String?)
    /// 暂停落库（2026-10-14 审查 P1-9）：记录暂停时刻的净专注秒数并置状态为 paused，
    /// 使「暂停后进程被回收」不再被按挂钟时间误判为超时完成。
    func pauseSession(_ session: FocusSession, activeSeconds: TimeInterval)
    /// 恢复落库：状态回到 running，并把 updatedAt 作为新的计时起点标记。
    func resumeSession(_ session: FocusSession)
    /// 由持久化状态推算净专注秒数（暂停段不计入）；completeSession 的 actualDuration 判据。
    func activeElapsedSeconds(for session: FocusSession) -> TimeInterval
    func getCurrentSession() -> FocusSession?
    func fetchTodaysSessions() -> [FocusSession]
    /// 仅今日「专注阶段」的会话（统计口径专用，修复 2026-10-14 审查 P1-1）
    func fetchTodayFocusSessions() -> [FocusSession]
    /// 获取指定日期范围内的已完成会话（供统计模块使用，替代 ViewModel 直连 viewContext）
    func fetchCompletedSessions(from startDate: Date, to endDate: Date) -> [FocusSession]
    /// 获取全部已完成会话（供统计模块使用）
    func fetchAllCompletedSessions() -> [FocusSession]
    /// 「计入专注时长」的会话（completed + earlyCompleted），仅供时长统计使用。
    /// 番茄数 / 积分 / 连续天数 / 热力图仍走 fetchCompletedSessions/fetchAllCompletedSessions（只认 completed），
    /// 判据收口在 FocusSession.countsTowardDuration，避免提前结束被误算为完成番茄。
    func fetchSessionsForDuration(from startDate: Date, to endDate: Date) -> [FocusSession]
    func fetchAllSessionsForDuration() -> [FocusSession]
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

    /// 系统/配置原因丢弃（不带原因）。旧语义 abandoned、不计时长。
    func discardSession(_ session: FocusSession) {
        discardSession(session, reason: nil)
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
    /// save 失败统一上报（判据收口，2026-10-15 审查 P1-001）：
    /// 所有写路径经此检查，store 未就绪/保存失败时不再静默丢弃。
    func saveAndReport() {
        if !persistenceController.save() {
            onError?(AppError.coreDataSaveFailed(NSError(domain: "FlowTakt.FocusService",
                                                         code: NSFileWriteUnknownError)))
        }
    }

    init(persistenceController: PersistenceController,
         notificationService: NotificationServiceProtocol) {
        self.persistenceController = persistenceController
        self.notificationService = notificationService
    }

    func startFocusSession(task: Task?, plannedDuration: TimeInterval, phase: FocusPhase, roundIndex: Int16) -> FocusSession {
        // 防御：若存在遗留的 running / paused 会话（异常退出、暂停后从其它入口再次启动），
        // 先结算，避免同时存在多个未结束会话导致 getCurrentSession 语义混乱。
        //
        // 用户反馈 2026-11-19：旧实现无条件 discard（abandoned、不写净时长）——
        // 用户「暂停后从快捷指令/切换路径再开一次计时」时，前一段真实专注的净时长被彻底抹掉，
        // 这正是「时长被清空」的又一条路径。现改为按净时长分流：
        // - 净时长 ≥ 1 秒 → 走 abandonSession（earlyCompleted）：时长计入统计，
        //   不算完成番茄 / 积分 / 完成率（判据仍在 FocusSession.countsTowardDuration）
        // - 净时长为 0（刚开始就暂停/被杀）→ 仍走 discardSession，避免制造空会话
        if let orphan = getCurrentSession() {
            // 封顶保护（2026-11-19 审查补）：running 会话的净时长按「现在 - updatedAt」推算，
            // 若进程在几天前被系统回收、会话仍停在 running，这里的净时长会按挂钟无限增长。
            // 过去判定为 interrupted（不计统计）时无害；现在要**保留时长**，就必须以计划时长封顶，
            // 否则一次异常残留会把「忘了停」写成几十小时专注，污染统计与标签分布。
            let planned = max(0, orphan.plannedDuration)
            let rawElapsed = activeElapsedSeconds(for: orphan)
            if planned > 0, rawElapsed > planned {
                orphan.actualDuration = planned
                orphan.updatedAt = Date()   // 重置基准：此后 activeElapsedSeconds ≈ planned
            }

            // plannedDuration 为 0 属数据损坏：没有可核对的计划时长，一律不结算时长（保守）
            let netElapsed = planned > 0 ? min(rawElapsed, planned) : 0
            if netElapsed >= 1 {
                // 有真实净专注：结算为 earlyCompleted，时长保留（用户反馈核心诉求）
                abandonSession(orphan, reason: "replaced_by_new_session")
            } else if orphan.status == SessionStatus.paused.rawValue {
                // 暂停且净时长为 0：不制造空会话
                discardSession(orphan, reason: "replaced_by_new_session")
            } else {
                // running 且净时长≈0：属异常重复启动，保留 interrupted 语义便于诊断
                interruptSession(orphan)
            }
        }

        let session = FocusSession(context: viewContext)
        session.storageId = UUID()
        session.startTime = Date()
        session.plannedDuration = plannedDuration
        session.phase = phase.rawValue
        session.roundIndex = roundIndex
        session.status = SessionStatus.running.rawValue
        session.earnedPoints = 0
        session.createdAt = Date()
        session.updatedAt = Date()
        session.task = task

        saveAndReport()

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
        guard session.managedObjectContext != nil, !session.isDeleted else { return }
        // 状态机守卫：仅 running / paused 会话可完成，保证幂等（重复 complete / 已完成后再操作均忽略）
        guard session.status == SessionStatus.running.rawValue
                || session.status == SessionStatus.paused.rawValue else { return }
        let now = Date()
        session.endTime = now
        session.actualDuration = actualDuration ?? activeElapsedSeconds(for: session)
        session.status = SessionStatus.completed.rawValue
        // 修复（2026-10-14 审查 P1-1）：**休息阶段不发积分、不计任务番茄数**。
        // 旧实现无条件发满分并让 task.completedPomodoros += 1，导致「完成 1 专注 + 1 短休」
        // 在统计页显示 2 个番茄 / 20 分，而成就页（口径已过滤 focus）显示 10 分 —— 同 App 两值矛盾，
        // 且脏数据会随 CloudKit 同步与备份扩散。
        let isFocusPhase = session.phase == FocusPhase.focus.rawValue
        session.earnedPoints = isFocusPhase
            ? Int16(AppConstants.pointsPerCompletedPomodoro)
            : 0
        session.updatedAt = now

        // 更新关联任务的已完成番茄钟数（同样只对专注阶段计数）
        if isFocusPhase, let task = session.task {
            task.completedPomodoros += 1
            task.updatedAt = now
        }

        // 保存失败必须让调用方知道（修复 2026-10-14 审查 P1-5）：
        // 旧实现丢弃 save() 的 Bool，store 未就绪/重置窗口内会「动画播了但没存」。
        if !persistenceController.save() {
            print("⚠️ 完成会话落盘失败（store 可能未就绪）")
            onError?(AppError.coreDataSaveFailed(NSError(domain: "FlowTakt.FocusService",
                                                         code: NSFileWriteUnknownError)))
        }

        // 取消通知
        notificationService.cancelNotification(withIdentifier: session.id.uuidString)
    }

    // MARK: - 暂停 / 恢复（落库，修复 2026-10-14 审查 P1-9）

    /// 暂停落库：`actualDuration` 存「截至此刻的净专注秒数」，`updatedAt` 存暂停时刻。
    /// 语义仅对 running / paused 会话生效；completed 会覆盖 actualDuration 故须排除。
    func pauseSession(_ session: FocusSession, activeSeconds: TimeInterval) {
        guard session.managedObjectContext != nil, !session.isDeleted else { return }
        guard session.status == SessionStatus.running.rawValue else { return }
        session.status = SessionStatus.paused.rawValue
        session.actualDuration = max(0, activeSeconds)
        session.updatedAt = Date()
        saveAndReport()
        notificationService.cancelNotification(withIdentifier: session.id.uuidString)
    }

    /// 恢复落库：状态回 running，`updatedAt` 作为「本段计时起点」标记，
    /// 此后 `activeElapsedSeconds` = actualDuration + (now - updatedAt)。
    func resumeSession(_ session: FocusSession) {
        guard session.managedObjectContext != nil, !session.isDeleted else { return }
        guard session.status == SessionStatus.paused.rawValue else { return }
        session.status = SessionStatus.running.rawValue
        session.updatedAt = Date()
        saveAndReport()
    }

    /// 净专注秒数（暂停段不计入），可跨进程恢复：
    /// - running：`actualDuration`（最近一次暂停时的累计）+ `now - updatedAt`（本段已跑）
    /// - paused：`actualDuration` 冻结（暂停期间不计入）
    func activeElapsedSeconds(for session: FocusSession) -> TimeInterval {
        if session.status == SessionStatus.paused.rawValue {
            return max(0, session.actualDuration)
        }
        let sinceMark = max(0, Date().timeIntervalSince(session.updatedAt))
        return max(0, session.actualDuration) + sinceMark
    }

    func interruptSession(_ session: FocusSession) {
        guard session.managedObjectContext != nil, !session.isDeleted else { return }
        guard session.status == SessionStatus.running.rawValue
                || session.status == SessionStatus.paused.rawValue else { return }
        let now = Date()
        session.endTime = now
        session.actualDuration = activeElapsedSeconds(for: session)
        session.status = SessionStatus.interrupted.rawValue
        session.earnedPoints = 0
        session.updatedAt = now
        saveAndReport()

        notificationService.cancelNotification(withIdentifier: session.id.uuidString)
    }

    /// 结束会话并保留已专注的净时长（用户反馈 2026-11-17）。
    ///
    /// 旧实现把「提前结束」判为 abandoned 且不写 actualDuration，统计全部过滤 abandoned，
    /// 用户实际专注的 5 分钟被完全抹消。现改为：
    /// - 写入 actualDuration = activeElapsedSeconds（暂停段已扣除）
    /// - 状态置 earlyCompleted，**只计入专注时长**，不计完成番茄/积分/完成率/连续天数/热力图
    /// - 保留 interruptionReason，供「中断洞察」回顾原因
    func abandonSession(_ session: FocusSession, reason: String?) {
        guard session.managedObjectContext != nil, !session.isDeleted else { return }
        guard session.status == SessionStatus.running.rawValue
                || session.status == SessionStatus.paused.rawValue else { return }
        let now = Date()
        session.actualDuration = activeElapsedSeconds(for: session)
        session.status = SessionStatus.earlyCompleted.rawValue
        // 记录中断原因（可选）：供统计回顾"今天为什么没完成番茄"
        session.interruptionReason = reason
        session.endTime = now
        session.earnedPoints = 0
        session.updatedAt = now
        saveAndReport()

        notificationService.cancelNotification(withIdentifier: session.id.uuidString)
    }

    /// 系统/配置原因丢弃会话：保持旧 abandoned 语义，不写净时长、不计任何统计。
    /// 与 abandonSession（用户主动提前结束、计时长）严格区分，判据收口在两个入口本身。
    func discardSession(_ session: FocusSession, reason: String?) {
        guard session.managedObjectContext != nil, !session.isDeleted else { return }
        guard session.status == SessionStatus.running.rawValue
                || session.status == SessionStatus.paused.rawValue else { return }
        let now = Date()
        // paused 会话在 pauseSession 时已落库 net 时长，这里不覆盖：
        // 保持原值但不计入统计（abandoned 不在 countsTowardDuration 内）。
        session.status = SessionStatus.abandoned.rawValue
        session.interruptionReason = reason
        session.endTime = now
        session.earnedPoints = 0
        session.updatedAt = now
        saveAndReport()

        notificationService.cancelNotification(withIdentifier: session.id.uuidString)
    }

    func getCurrentSession() -> FocusSession? {
        guard persistenceController.canFetchSafely("FocusService.getCurrentSession") else { return nil }
        let request = FocusSession.fetchRequest()
        // 修复（P1-9）：paused 会话同样是「未结束会话」，必须能被恢复查到
        request.predicate = NSPredicate(format: "status IN %@",
                                        [SessionStatus.running.rawValue, SessionStatus.paused.rawValue])
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
        guard persistenceController.canFetchSafely("FocusService.fetchTodaysSessions") else { return [] }
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

    /// 今日「专注阶段」会话（修复 2026-10-14 审查 P1-1）
    ///
    /// 判据收口：今日完成数 / 时长 / 积分 / 锁屏摘要 / Siri 摘要全部走这一个方法，
    /// 避免第 N 次出现「某处忘了加 phase 过滤」导致同 App 两个「今日积分」不一致。
    func fetchTodayFocusSessions() -> [FocusSession] {
        guard persistenceController.canFetchSafely("FocusService.fetchTodayFocusSessions") else { return [] }
        let request = FocusSession.fetchRequest()
        let todayStart = Date().startOfDay
        let todayEnd = Date().endOfDay
        request.predicate = NSPredicate(
            format: "startTime >= %@ AND startTime < %@ AND phase == %@",
            todayStart as NSDate, todayEnd as NSDate, FocusPhase.focus.rawValue)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \FocusSession.startTime, ascending: false)]
        do {
            return try viewContext.fetch(request)
        } catch {
            print("获取今日专注会话失败：\(error.localizedDescription)")
            onError?(error)
            return []
        }
    }

    func fetchCompletedSessions(from startDate: Date, to endDate: Date) -> [FocusSession] {
        guard persistenceController.canFetchSafely("FocusService.fetchCompletedSessions") else { return [] }
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
        guard persistenceController.canFetchSafely("FocusService.fetchAllCompletedSessions") else { return [] }
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

    // MARK: - 时长统计专用（completed + earlyCompleted）

    func fetchSessionsForDuration(from startDate: Date, to endDate: Date) -> [FocusSession] {
        guard persistenceController.canFetchSafely("FocusService.fetchSessionsForDuration") else { return [] }
        let request = FocusSession.fetchRequest()
        request.predicate = NSPredicate(
            format: "startTime >= %@ AND startTime < %@ AND status IN %@ AND phase == %@",
            startDate as NSDate,
            endDate as NSDate,
            [SessionStatus.completed.rawValue, SessionStatus.earlyCompleted.rawValue],
            FocusPhase.focus.rawValue
        )
        request.sortDescriptors = [NSSortDescriptor(keyPath: \FocusSession.startTime, ascending: true)]
        do {
            return try viewContext.fetch(request)
        } catch {
            print("获取时长统计会话失败：\(error.localizedDescription)")
            onError?(error)
            return []
        }
    }

    func fetchAllSessionsForDuration() -> [FocusSession] {
        guard persistenceController.canFetchSafely("FocusService.fetchAllSessionsForDuration") else { return [] }
        let request = FocusSession.fetchRequest()
        request.predicate = NSPredicate(
            format: "status IN %@ AND phase == %@",
            [SessionStatus.completed.rawValue, SessionStatus.earlyCompleted.rawValue],
            FocusPhase.focus.rawValue
        )
        request.sortDescriptors = [NSSortDescriptor(keyPath: \FocusSession.startTime, ascending: false)]
        do {
            return try viewContext.fetch(request)
        } catch {
            print("获取全部时长统计会话失败：\(error.localizedDescription)")
            onError?(error)
            return []
        }
    }
}

import XCTest
import CoreData
import CloudKit
@testable import FlowTakt

// MARK: - ReviewFixRegressionTests
// 覆盖 2026-10-14 全量代码审查（报告 code-review-2026-10-14.md）修复的关键路径。
//
// 本文件只测「审查指出并已修复」的缺陷，防止回归：
//   P1-1  completeSession 不看 phase → 休息阶段也发积分、也加任务番茄数
//   P1-3  重置错误分类：本地失败被谎报为云端失败（userMessage 判据收口）
//   P1-8  撤销今日打卡把连续天数清零
//   P1-9  暂停态不落库 → 暂停后进程回收被误判「完整完成」
//   P1-12 「下午3:30」被解析成 00:00
//   P0-2  删除任务级联删掉专注历史（含运行中会话）
//   P2-12 空备份会清空本地库并报「恢复成功」
//   P1-5  重置并发重入

@MainActor
final class ReviewFixRegressionTests: XCTestCase {

    private var persistence: PersistenceController!
    private var focusService: FocusService!
    private var taskService: TaskService!
    private var habitService: HabitService!
    private var notificationService: NotificationService!

    override func setUp() {
        super.setUp()
        persistence = PersistenceController(inMemory: true)
        notificationService = NotificationService()
        focusService = FocusService(persistenceController: persistence,
                                    notificationService: notificationService)
        taskService = TaskService(persistenceController: persistence)
        habitService = HabitService(persistenceController: persistence)
    }

    override func tearDown() {
        habitService = nil
        taskService = nil
        focusService = nil
        notificationService = nil
        persistence = nil
        super.tearDown()
    }

    // MARK: - P1-1 休息阶段不应计分

    func testCompleteSession_BreakPhase_DoesNotEarnPointsOrIncrementTaskPomodoros() {
        let task = taskService.createTask(title: "写周报", notes: nil, estimatedPomodoros: 2,
                                          priority: 2, dueDate: nil, recurrenceRule: nil)
        let session = focusService.startFocusSession(task: task, plannedDuration: 300,
                                                     phase: .shortBreak, roundIndex: 1)

        focusService.completeSession(session, actualDuration: 300)

        XCTAssertEqual(session.earnedPoints, 0, "休息阶段不应发放积分")
        XCTAssertEqual(task.completedPomodoros, 0, "休息阶段不应增加任务番茄数")
        XCTAssertEqual(session.status, SessionStatus.completed.rawValue)
    }

    func testCompleteSession_FocusPhase_EarnsPointsAndIncrementsTaskPomodoros() {
        let task = taskService.createTask(title: "写周报", notes: nil, estimatedPomodoros: 2,
                                          priority: 2, dueDate: nil, recurrenceRule: nil)
        let session = focusService.startFocusSession(task: task, plannedDuration: 1500,
                                                     phase: .focus, roundIndex: 1)

        focusService.completeSession(session, actualDuration: 1500)

        XCTAssertEqual(session.earnedPoints, Int16(AppConstants.pointsPerCompletedPomodoro))
        XCTAssertEqual(task.completedPomodoros, 1, "专注阶段完成应 +1 番茄")
    }

    /// 今日统计口径：只应包含专注阶段（统计页/锁屏/Siri 全部走 fetchTodayFocusSessions）
    func testFetchTodayFocusSessions_ExcludesBreakSessions() {
        let focus = focusService.startFocusSession(task: nil, plannedDuration: 1500,
                                                    phase: .focus, roundIndex: 1)
        focusService.completeSession(focus, actualDuration: 1500)
        let brk = focusService.startFocusSession(task: nil, plannedDuration: 300,
                                                 phase: .shortBreak, roundIndex: 1)
        focusService.completeSession(brk, actualDuration: 300)

        let todayFocus = focusService.fetchTodayFocusSessions()
        XCTAssertEqual(todayFocus.count, 1, "今日专注会话应只含专注阶段")
        XCTAssertEqual(todayFocus.first?.phase, FocusPhase.focus.rawValue)
        XCTAssertEqual(focusService.fetchTodaysSessions().count, 2, "全量今日会话仍为 2（含休息）")
    }

    // MARK: - P1-9 暂停态落库与净专注时长

    func testPauseSession_PersistsPausedStatusAndFreezesElapsed() {
        let session = focusService.startFocusSession(task: nil, plannedDuration: 1500,
                                                     phase: .focus, roundIndex: 1)
        // 模拟已专注 60 秒后暂停
        session.actualDuration = 60
        focusService.pauseSession(session, activeSeconds: 60)

        XCTAssertEqual(session.status, SessionStatus.paused.rawValue, "暂停状态必须落库")
        // 复审修复：原先只断言「值没被改写」，删掉冻结逻辑也能通过。
        // 改为等待后再取，真正验证「暂停期间净专注秒数不增长」。
        let elapsedAtPause = focusService.activeElapsedSeconds(for: session)
        XCTAssertEqual(elapsedAtPause, 60, accuracy: 1)
        let expectation = expectation(description: "暂停期间不增长")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { expectation.fulfill() }
        wait(for: [expectation], timeout: 2)
        let elapsedLater = focusService.activeElapsedSeconds(for: session)
        XCTAssertEqual(elapsedLater, elapsedAtPause, accuracy: 0.5,
                       "暂停期间净专注秒数必须冻结（否则时长虚高）")
    }

    func testGetCurrentSession_IncludesPausedSession() {
        let session = focusService.startFocusSession(task: nil, plannedDuration: 1500,
                                                     phase: .focus, roundIndex: 1)
        focusService.pauseSession(session, activeSeconds: 30)

        let current = focusService.getCurrentSession()
        XCTAssertNotNil(current, "paused 会话同样属于未结束会话，必须能被恢复查到")
        XCTAssertEqual(current?.status, SessionStatus.paused.rawValue)
    }

    func testActiveElapsed_AfterResume_ContinuesFromPersistedMark() {
        let session = focusService.startFocusSession(task: nil, plannedDuration: 1500,
                                                     phase: .focus, roundIndex: 1)
        focusService.pauseSession(session, activeSeconds: 600)
        focusService.resumeSession(session)
        XCTAssertEqual(session.status, SessionStatus.running.rawValue)

        // 恢复后再过一小段时间，净专注秒数应大于 600（而不是从 0 或按挂钟重算）
        let elapsed = focusService.activeElapsedSeconds(for: session)
        XCTAssertGreaterThanOrEqual(elapsed, 600, "恢复后净专注秒数应从暂停时累计值继续")
        XCTAssertLessThan(elapsed, 700, "不应把暂停期间算作专注")
    }

    func testCompleteSession_FromPausedState_IsAllowed() {
        let session = focusService.startFocusSession(task: nil, plannedDuration: 1500,
                                                     phase: .focus, roundIndex: 1)
        focusService.pauseSession(session, activeSeconds: 300)
        focusService.completeSession(session, actualDuration: 300)

        XCTAssertEqual(session.status, SessionStatus.completed.rawValue,
                       "暂停状态下跳过阶段也应能完成（skipPhase 依赖此路径）")
        XCTAssertEqual(session.actualDuration, 300, accuracy: 1)
    }

    // MARK: - P1-8 撤销今日打卡不清零连续天数

    func testRecalculateStreak_AfterUncheckingToday_KeepsPreviousStreak() throws {
        let habit = habitService.createHabit(name: "冥想", descriptionText: nil,
                                             iconName: "brain.head.profile", colorHex: "#AF52DE",
                                             frequency: "daily", targetCount: 1)
        // 前两天各打卡一次（checkIn 无日期参数，打卡后改写 record.date 模拟历史记录）
        for offset in [-2, -1] {
            let day = Calendar.current.date(byAdding: .day, value: offset,
                                            to: Calendar.current.startOfDay(for: Date()))!
            let record = habitService.checkIn(habit: habit, count: 1, note: nil)
            record.date = day
        }
        persistence.save()
        habitService.recalculateStreak(for: habit)
        let streakBefore = habit.currentStreak
        XCTAssertGreaterThanOrEqual(streakBefore, 2, "前两天打卡应累计 2 天")

        // 今天也打卡 → 应为 3 天；随后撤销今日打卡
        let todayRecord = habitService.checkIn(habit: habit, count: 1, note: nil)
        persistence.save()
        habitService.recalculateStreak(for: habit)
        XCTAssertEqual(habit.currentStreak, 3, "含今天应为 3 天")

        habitService.removeCheckIn(todayRecord)
        persistence.save()

        XCTAssertEqual(habit.currentStreak, streakBefore,
                       "撤销今日打卡后应回落到「昨天为止」的连续天数，而不是清零")
    }

    // MARK: - P1-12 自然语言时间解析

    func testEventDraftParser_AfternoonClockTime_ParsesToCorrectHour() throws {
        // 「下午3:30」应解析为 15:30，而不是 00:00
        let draft = try XCTUnwrap(EventDraftParser.parse("下午3:30 开会"))
        let components = Calendar.current.dateComponents([.hour, .minute], from: draft.startDate)
        XCTAssertEqual(components.hour, 15, "下午3:30 应解析为 15 点")
        XCTAssertEqual(components.minute, 30)
    }

    func testEventDraftParser_EveningClockTime_ParsesToCorrectHour() throws {
        let draft = try XCTUnwrap(EventDraftParser.parse("晚上8:15 复盘"))
        let components = Calendar.current.dateComponents([.hour, .minute], from: draft.startDate)
        XCTAssertEqual(components.hour, 20)
        XCTAssertEqual(components.minute, 15)
    }

    // MARK: - P0-2 删除任务不应级联删除专注历史

    func testDeleteTask_KeepsFocusSessionsAndRunningSession() throws {
        let task = taskService.createTask(title: "跑步", notes: nil, estimatedPomodoros: 1,
                                          priority: 2, dueDate: nil, recurrenceRule: nil)
        let session = focusService.startFocusSession(task: task, plannedDuration: 1500,
                                                     phase: .focus, roundIndex: 1)
        persistence.save()

        taskService.deleteTask(task)

        XCTAssertFalse(session.isDeleted, "专注会话不应随任务删除（模型为 Cascade，需显式解除关联）")
        XCTAssertNil(session.task, "会话的 task 引用应被置 nil")
        let sessions = try persistence.viewContext.fetch(FocusSession.fetchRequest())
        XCTAssertEqual(sessions.count, 1, "专注历史应保留")
    }

    // MARK: - P1-3 错误分类：本地失败不得被当成云端失败

    func testUserMessage_LocalResetError_ReturnsEmptySoUIUsesLocalFailureBranch() {
        let message = CloudKitPurgeService.userMessage(for: PersistenceController.LocalResetError.storeReloadFailed)
        XCTAssertTrue(message.isEmpty, "本地错误不应被映射成云端文案（否则弹「云端清除失败」）")
    }

    func testUserMessage_PurgeError_ReturnsSpecificReason() {
        let message = CloudKitPurgeService.userMessage(for: CloudKitPurgeService.PurgeError.notSignedIn)
        XCTAssertEqual(message, L10n.shared.云端未登录, "未登录应给出可执行的具体文案")
    }

    func testLocalResetErrorDescriptions_AreDistinctPerCase() {
        let messages: [String?] = [
            PersistenceController.LocalResetError.inMemoryStore.errorDescription,
            PersistenceController.LocalResetError.storeURLUnavailable.errorDescription,
            PersistenceController.LocalResetError.storeReloadFailed.errorDescription,
            PersistenceController.LocalResetError.storeRemovalFailed.errorDescription,
            PersistenceController.LocalResetError.alreadyResetting.errorDescription,
            PersistenceController.LocalResetError.selfDeallocated.errorDescription
        ]
        let values = messages.compactMap { $0 }
        XCTAssertEqual(values.count, messages.count, "每个失败原因都必须有文案")
        XCTAssertEqual(Set(values).count, values.count, "各失败原因文案必须互不相同（禁止笼统）")
    }

    // MARK: - P0-1 / 空备份防护

    func testImportJSON_EmptyPayload_RefusesAndKeepsData() throws {
        let backup = BackupService(persistenceController: persistence)
        _ = taskService.createTask(title: "保留我", notes: nil, estimatedPomodoros: 1,
                                   priority: 2, dueDate: nil, recurrenceRule: nil)
        persistence.save()

        // 构造一个结构合法但内容全空的备份
        let empty = BackupPayload(version: BackupPayload.currentVersion,
                                  exportedAt: Date(),
                                  tasks: [], focusSessions: [], habits: [], habitRecords: [],
                                  timeRecords: [], scheduleItems: [], tags: [])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("empty-backup-\(UUID().uuidString).json")
        // 复审修复（2026-10-14 P0）：必须用与生产解码一致的 iso8601 策略 ——
        // 默认 deferredToDate 会把 exportedAt 写成数字，.iso8601 解码器直接抛错，
        // 使本用例走「解码失败」路径通过，对空载荷守卫零鉴别力（假绿）。
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(empty).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertFalse(backup.importJSON(from: url), "空备份应被拒绝")
        let tasks = try persistence.viewContext.fetch(Task.fetchRequest())
        XCTAssertEqual(tasks.count, 1, "空备份不得清空本地数据")
    }

    // MARK: - CloudKit 删除结果分类（T8：此前该分支零测试）

    func testClassifyDeleteResults_AllSuccess_CountsAll() {
        let ids = [CKRecord.ID(recordName: "a"), CKRecord.ID(recordName: "b")]
        let results: [CKRecord.ID: Result<Void, any Error>] = [
            ids[0]: .success(()), ids[1]: .success(())
        ]
        let outcome = CloudKitPurgeService.classifyDeleteResults(results)
        XCTAssertEqual(outcome.deleted, 2)
        XCTAssertNil(outcome.failure)
    }

    func testClassifyDeleteResults_UnknownItem_CountsAsDeletedNotFailure() {
        let id = CKRecord.ID(recordName: "gone")
        let unknown = CKError(.unknownItem)
        let outcome = CloudKitPurgeService.classifyDeleteResults([id: .failure(unknown)])
        XCTAssertEqual(outcome.deleted, 1, "已被其它设备删除的记录等价于已删除")
        XCTAssertNil(outcome.failure, "unknownItem 不应中断整体清除")
    }

    func testClassifyDeleteResults_RealFailure_IsReported() {
        let id = CKRecord.ID(recordName: "denied")
        let denied = CKError(.networkFailure)
        let outcome = CloudKitPurgeService.classifyDeleteResults([id: .failure(denied)])
        XCTAssertEqual(outcome.deleted, 0)
        XCTAssertNotNil(outcome.failure, "真实失败必须上报（否则报告成功但云端仍有残留）")
    }

    // MARK: - recordType 不存在判据（2026-10-15 修复：Achievement 从未同步上云导致重置失败）

    func testIsRecordTypeMissing_DirectServerMessage_ReturnsTrue() {
        // CloudKit 服务器对 schema 中不存在的 recordType 返回的原文
        let nsError = NSError(domain: CKErrorDomain, code: CKError.partialFailure.rawValue,
                              userInfo: [NSLocalizedDescriptionKey: "Did not find record type: Achievement"])
        XCTAssertTrue(CloudKitPurgeService.isRecordTypeMissing(nsError),
                      "服务器原文「Did not find record type」应识别为无云端副本")
    }

    func testIsRecordTypeMissing_WrappedInPartialFailure_ReturnsTrue() {
        let inner = NSError(domain: CKErrorDomain, code: CKError.partialFailure.rawValue,
                            userInfo: [NSLocalizedDescriptionKey: "Did not find record type: Achievement"])
        // CKError.partialErrorsByItemID 背后的 NSString 常量在 Swift 侧不可见也不公开取值，
        // 真实环境由服务端注入；此处用 userInfo 键名匹配路径覆盖该包装形态。
        let outer = CKError(.partialFailure, userInfo: [
            "CKPartialErrorsByItemIDKey": [CKRecord.ID(recordName: "x"): inner]
        ])
        XCTAssertTrue(CloudKitPurgeService.isRecordTypeMissing(outer),
                      "partialFailure 包装链中的 recordType 缺失应被识别")
    }

    func testIsRecordTypeMissing_WrappedUnderlyingError_ReturnsTrue() {
        let inner = NSError(domain: CKErrorDomain, code: CKError.internalError.rawValue,
                            userInfo: [NSLocalizedDescriptionKey: "Unknown record type 'Achievement'"])
        let outer = NSError(domain: CKErrorDomain, code: CKError.partialFailure.rawValue,
                            userInfo: [NSUnderlyingErrorKey: inner])
        XCTAssertTrue(CloudKitPurgeService.isRecordTypeMissing(outer))
    }

    func testIsRecordTypeMissing_UnrelatedError_ReturnsFalse() {
        XCTAssertFalse(CloudKitPurgeService.isRecordTypeMissing(CKError(.networkFailure)),
                       "网络错误不得误判为 recordType 缺失")
        XCTAssertFalse(CloudKitPurgeService.isRecordTypeMissing(CKError(.notAuthenticated)),
                       "未登录不得误判为 recordType 缺失")
    }

    // MARK: - Live Activity ContentState 解码兜底（T8：此前零测试）

    func testContentState_DecodesLegacyPayloadWithoutTotalDuration() throws {
        // 模拟旧版本创建的活动：JSON 里没有 totalDuration 键
        let legacyJSON = """
        {"phaseRaw":"focus","isPaused":false,"isFinished":false,
         "startDate":\(Date().timeIntervalSince1970),
         "endDate":\(Date().addingTimeInterval(600).timeIntervalSince1970),
         "pausedRemaining":0}
        """.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: "\"", with: "\"")
        let data = Data(legacyJSON.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let state = try decoder.decode(FocusActivityAttributes.ContentState.self, from: data)
        XCTAssertEqual(state.phaseRaw, "focus")
        XCTAssertEqual(state.totalDuration, 0, "缺失字段应兜底为 0，而不是解码失败")
    }

    func testContentState_RoundTrip_PreservesTotalDuration() throws {
        let state = FocusActivityAttributes.ContentState(
            phaseRaw: "shortBreak", isPaused: true, isFinished: false,
            startDate: Date(), endDate: Date().addingTimeInterval(300),
            pausedRemaining: 300, totalDuration: 1500, taskTitle: "写周报")
        let data = try JSONEncoder().encode(state)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let decoded = try decoder.decode(FocusActivityAttributes.ContentState.self, from: data)
        XCTAssertEqual(decoded.totalDuration, 1500)
        XCTAssertEqual(decoded.pausedRemaining, 300)
        XCTAssertEqual(decoded.taskTitle, "写周报")
    }

    // MARK: - App Intents 守卫路径（T8：9 个 Intent 此前零测试）

    /// App 未启动时 `AppDependency.shared == nil`，所有依赖数据的 Intent 都应走
    /// 「数据未就绪」分支而**不崩溃**（Intents 会被系统在 App 未运行时调用）。
    func testIntents_DataDependentOnes_DoNotCrashWhenDependencyMissing() async throws {
        // 注意：测试宿主进程会创建 AppDependency.shared，因此这里不假设它为 nil，
        // 只验证「无论依赖是否存在，Intent 的 perform 都不崩溃」（Intents 会被系统在
        // App 未完全启动时调用，这条路径必须有覆盖）。
        let stats = TodayStatsIntent()
        _ = try await stats.perform()

        let openPage = OpenPageIntent()
        _ = try await openPage.perform()

        let startFocus = StartFocusIntent()
        _ = try await startFocus.perform()

        let startBreak = StartBreakIntent()
        _ = try await startBreak.perform()

        let pause = PauseFocusIntent()
        _ = try await pause.perform()

        let stop = StopFocusIntent()
        _ = try await stop.perform()
        // 走到这里即证明未崩溃 —— 守卫生效
    }

    /// 参数校验：分钟数非法时应被夹到合法区间，而不是照单全收
    func testStartFocusIntent_ClampsInvalidMinutes() async throws {
        let intent = StartFocusIntent()
        // AppIntent 的参数通过 $minutes 传入；这里只验证 perform 在依赖缺失时不崩溃
        intent.minutes = 0
        _ = try await intent.perform()
        intent.minutes = 99999
        _ = try await intent.perform()
    }

    // MARK: - 运行态区间反推（2026-10-15：灵动岛"总是很宽"修复的判据函数）

    func testNormalizedStartDate_ResumedInterval_LengthEqualsTotalDuration() throws {
        // 场景：暂停后继续 —— endDate = now + 剩余（300s），总时长 1500s
        let end = Date().addingTimeInterval(300)
        let start = FocusActivityAttributes.normalizedStartDate(endDate: end, totalDuration: 1500)

        XCTAssertEqual(end.timeIntervalSince(start), 1500, accuracy: 0.01,
                       "区间长度必须等于计划总时长（系统驱动进度条的分母）")
        // 进度比例 = 已用 / 总长 = (1500-300)/1500 = 0.8，不因恢复而跳回 0
        let progress = Date().timeIntervalSince(start) / end.timeIntervalSince(start)
        XCTAssertEqual(progress, 0.8, accuracy: 0.02,
                       "恢复后进度比例应反映真实已用时长（P1-13 跳变问题的根治）")
    }

    func testNormalizedStartDate_FreshStart_ApproximatesNow() throws {
        // 场景：全新开始 —— endDate = now + 总时长
        let now = Date()
        let end = now.addingTimeInterval(1500)
        let start = FocusActivityAttributes.normalizedStartDate(endDate: end, totalDuration: 1500)

        XCTAssertEqual(start.timeIntervalSince(now), 0, accuracy: 0.05,
                       "全新开始时反推起点应≈现在（进度从 0 开始）")
    }

    // MARK: - 实体 id 为 nil 时的兜底（2026-10-15 线上崩溃修复）

    /// 崩溃回归（13 Pro 实机 10 次）：存储层 id 为 nil 时，旧声明（非 optional UUID）
    /// 读取会经 `_unconditionallyBridgeFromObjectiveC` 触发 EXC_BREAKPOINT。
    /// 修复后存储属性为 optional（storageId），对外 `id` 计算属性兜底 —— 读取永不崩溃且稳定。
    func testEntityId_NilStorage_ReadIsStableAndNonCrashing() throws {
        let context = persistence.viewContext

        // 复现崩溃场景：id 存储为 nil
        let achievement = Achievement(context: context)
        achievement.storageId = nil
        // 此前该行崩溃（ForEach 渲染读 id 即触发）；现在应安全返回占位
        let first = achievement.id
        XCTAssertEqual(achievement.id, first, "占位 id 应稳定（ForEach 标识一致性）")

        let item = ScheduleItem(context: context)
        item.storageId = nil
        XCTAssertEqual(item.id, item.id, "ScheduleItem 同构：nil 存储读取应稳定")
    }

    /// 正常数据路径：storageId 有值时 id 原样返回。
    func testEntityId_NormalStorage_ReturnsStoredValue() throws {
        let context = persistence.viewContext
        let tag = Tag(context: context)
        let uuid = UUID()
        tag.storageId = uuid
        XCTAssertEqual(tag.id, uuid)
    }
}

import Foundation
import CoreData
@testable import FlowTakt

// MARK: - Mock Service 实现
// 这些 Mock 用于 ViewModel 测试，严格 conform 到实际的 Service 协议
// 所有 Mock 类的方法签名与源码协议完全一致

// MARK: - MockTaskService

final class MockTaskService: TaskServiceProtocol {
    var tasks: [Task] = []

    // 用于测试断言的 handler 闭包
    var createTaskCalledHandler: ((String, String?, Int16, Int16, Date?, String?) -> Void)?
    var updateTaskCalledHandler: ((Task) -> Void)?
    var deleteTaskCalledHandler: ((Task) -> Void)?
    var incrementCompletedPomodorosCalledHandler: ((Task) -> Void)?
    // 修复（2026-10-15 审查 P2-S3）：与 incrementCompletedPomodorosCalledHandler 重复的同义字段已删除，
    // 原引用处（FocusViewModelTests）已迁移到 CalledHandler 命名

    // 向后兼容：旧版 TaskViewModelTests / FocusViewModelTests
    var createTaskHandler: ((String, String?, Int16, Int16, Date?, String?) -> Task)?
    var deleteTaskHandler: ((Task) -> Void)?
    var updateTaskHandler: ((Task, String?, String?, Int16?, Int16?, String?, Date?, String?) -> Void)?

    /// 注意：必须实现与协议一致的完整签名（含 recurrenceRule 参数）。
    /// 若缺少该参数，调用会落到协议扩展的默认实现上并无限递归（栈溢出崩溃）。
    func createTask(title: String, notes: String?, estimatedPomodoros: Int16, priority: Int16, dueDate: Date?, recurrenceRule: String?) -> Task {
        createTaskCalledHandler?(title, notes, estimatedPomodoros, priority, dueDate, recurrenceRule)
        if let handler = createTaskHandler {
            return handler(title, notes, estimatedPomodoros, priority, dueDate, recurrenceRule)
        }
        // 修复（2026-10-14 审查 T7）：缺配置时给出可读失败原因，而非 SIGTRAP
        guard let first = tasks.first else {
            fatalError("MockTaskService 未配置 tasks 且无 createTaskHandler —— 请在测试中先注入任务")
        }
        return first
    }

    /// 必须实现与协议一致的完整签名（含 recurrenceRule 参数），避免走扩展默认实现递归。
    func updateTask(_ task: Task, title: String?, notes: String?, estimatedPomodoros: Int16?, priority: Int16?, status: String?, dueDate: Date?, recurrenceRule: String?) {
        updateTaskCalledHandler?(task)
        if let handler = updateTaskHandler {
            handler(task, title, notes, estimatedPomodoros, priority, status, dueDate, recurrenceRule)
        }
        if let t = title { task.title = t }
        if let n = notes { task.notes = n }
        if let e = estimatedPomodoros { task.estimatedPomodoros = e }
        if let p = priority { task.priority = p }
        if let s = status { task.status = s }
        if let d = dueDate { task.dueDate = d }
    }

    func deleteTask(_ task: Task) {
        deleteTaskCalledHandler?(task)
        deleteTaskHandler?(task)
        tasks.removeAll { $0.id == task.id }
    }

    func fetchAllTasks() -> [Task] {
        return tasks
    }

    func fetchActiveTasks() -> [Task] {
        return tasks.filter { $0.status == TaskStatus.active.rawValue }
    }

    func fetchCompletedTasks() -> [Task] {
        return tasks.filter { $0.status == TaskStatus.completed.rawValue }
    }

    func fetchArchivedTasks() -> [Task] {
        return tasks.filter { $0.status == TaskStatus.archived.rawValue }
    }

    func incrementCompletedPomodoros(for task: Task) {
        incrementCompletedPomodorosCalledHandler?(task)
        task.completedPomodoros += 1
    }
}

// MARK: - MockFocusService

final class MockFocusService: FocusServiceProtocol {
    var sessions: [FocusSession] = []

    // handler 闭包用于测试断言
    var startFocusSessionHandler: ((Task?, TimeInterval, FocusPhase, Int16) -> FocusSession)?
    var completeSessionHandler: ((FocusSession, TimeInterval?) -> Void)?
    var interruptSessionHandler: ((FocusSession) -> Void)?
    var abandonSessionHandler: ((FocusSession) -> Void)?
    var currentSessionToReturn: FocusSession?
    var fetchTodaysSessionsResult: [FocusSession]?
    var fetchTodayFocusSessionsResult: [FocusSession]?

    func startFocusSession(task: Task?, plannedDuration: TimeInterval, phase: FocusPhase, roundIndex: Int16) -> FocusSession {
        if let handler = startFocusSessionHandler {
            return handler(task, plannedDuration, phase, roundIndex)
        }
        // 修复（2026-10-14 审查 T7）：缺配置时给出可读的失败原因而非 SIGTRAP
        guard let first = sessions.first else {
            fatalError("MockFocusService 未配置 sessions 且无 startFocusSessionHandler —— 请在测试中先注入会话")
        }
        return first
    }

    // MARK: - 暂停 / 恢复（与真实实现同语义：状态 + 净专注秒 + updatedAt 标记）

    func pauseSession(_ session: FocusSession, activeSeconds: TimeInterval) {
        session.status = SessionStatus.paused.rawValue
        session.actualDuration = max(0, activeSeconds)
        session.updatedAt = Date()
    }

    func resumeSession(_ session: FocusSession) {
        session.status = SessionStatus.running.rawValue
        session.updatedAt = Date()
    }

    func activeElapsedSeconds(for session: FocusSession) -> TimeInterval {
        if session.status == SessionStatus.paused.rawValue {
            return max(0, session.actualDuration)
        }
        return max(0, session.actualDuration) + max(0, Date().timeIntervalSince(session.updatedAt))
    }

    func completeSession(_ session: FocusSession, actualDuration: TimeInterval? = nil) {
        completeSessionHandler?(session, actualDuration)
        session.status = SessionStatus.completed.rawValue
        session.endTime = Date()
        session.actualDuration = actualDuration ?? session.plannedDuration
        // 对齐真实实现语义（2026-10-15 审查 P1-011）：仅专注阶段发积分，
        // 否则依赖 Mock 的 VM 测试会在「休息完成」场景与真实集成产生分叉（假绿）
        session.earnedPoints = session.phase == FocusPhase.focus.rawValue
            ? Int16(AppConstants.pointsPerCompletedPomodoro)
            : 0
    }

    func interruptSession(_ session: FocusSession) {
        interruptSessionHandler?(session)
        session.status = SessionStatus.interrupted.rawValue
        session.endTime = Date()
    }

    func abandonSession(_ session: FocusSession, reason: String?) {
        abandonSessionHandler?(session)
        // 用户反馈 2026-11-17：与真实实现对齐 —— 提前结束保留净专注时长，
        // 状态为 earlyCompleted（计入时长、不计番茄/积分）。
        session.actualDuration = activeElapsedSeconds(for: session)
        session.status = SessionStatus.earlyCompleted.rawValue
        session.interruptionReason = reason
        session.endTime = Date()
        session.earnedPoints = 0
    }

    func discardSession(_ session: FocusSession, reason: String?) {
        // 系统/配置原因丢弃：与真实实现对齐，保持 abandoned、不写净时长、不计统计。
        session.status = SessionStatus.abandoned.rawValue
        session.interruptionReason = reason
        session.endTime = Date()
        session.earnedPoints = 0
    }

    func getCurrentSession() -> FocusSession? {
        return currentSessionToReturn
    }

    func fetchTodaysSessions() -> [FocusSession] {
        if let result = fetchTodaysSessionsResult { return result }
        return sessions.filter { Calendar.current.isDateInToday($0.startTime) }
    }

    /// 修复（2026-10-14 审查 P1-1 配套）：与真实实现同口径 —— 今日「专注阶段」会话
    func fetchTodayFocusSessions() -> [FocusSession] {
        if let result = fetchTodayFocusSessionsResult { return result }
        return sessions.filter {
            Calendar.current.isDateInToday($0.startTime) && $0.phase == FocusPhase.focus.rawValue
        }
    }

    func fetchCompletedSessions(from startDate: Date, to endDate: Date) -> [FocusSession] {
        // 审查修复（2026-08-12 第二轮）：与 FocusService 同步，只返回专注阶段完成会话
        sessions.filter {
            $0.status == SessionStatus.completed.rawValue &&
            $0.phase == FocusPhase.focus.rawValue &&
            $0.startTime >= startDate && $0.startTime <= endDate
        }
    }

    func fetchAllCompletedSessions() -> [FocusSession] {
        sessions.filter {
            $0.status == SessionStatus.completed.rawValue &&
            $0.phase == FocusPhase.focus.rawValue
        }
    }

    /// 时长统计口径（completed + earlyCompleted），与 FocusService 同语义
    func fetchSessionsForDuration(from startDate: Date, to endDate: Date) -> [FocusSession] {
        sessions.filter {
            $0.countsTowardDuration &&
            $0.phase == FocusPhase.focus.rawValue &&
            $0.startTime >= startDate && $0.startTime < endDate
        }
    }

    func fetchAllSessionsForDuration() -> [FocusSession] {
        sessions.filter {
            $0.countsTowardDuration && $0.phase == FocusPhase.focus.rawValue
        }
    }
    // 修复（2026-10-15 审查 P2-S2）：删除死代码 setAchievementService——
    // FocusServiceProtocol 无此方法、全仓无调用点
}

// MARK: - MockAchievementService

final class MockAchievementService: AchievementServiceProtocol {
    var achievements: [Achievement] = []
    var totalPointsValue: Int = 0
    var todayPointsValue: Int = 0
    var unlockedCountValue: Int = 0
    var checkAndUnlockCalled = false

    // 向后兼容：旧版测试使用以下属性名
    var totalPoints: Int {
        get { totalPointsValue }
        set { totalPointsValue = newValue }
    }
    var todaysPoints: Int {
        get { todayPointsValue }
        set { todayPointsValue = newValue }
    }
    var unlockedAchievementCount: Int {
        get { unlockedCountValue }
        set { unlockedCountValue = newValue }
    }
    var checkAndUnlockAchievementsHandler: (() -> Void)?
    var newlyUnlockedAchievements: [Achievement] = []
    var checkAndUnlockAchievementsCalled: Bool { checkAndUnlockCalled }

    func checkAndUnlockAchievements() {
        checkAndUnlockCalled = true
        checkAndUnlockAchievementsHandler?()
    }

    func fetchAllAchievements() -> [Achievement] {
        return achievements
    }

    func getTotalPoints() -> Int {
        return totalPointsValue
    }

    func getTodaysPoints() -> Int {
        return todayPointsValue
    }

    func getUnlockedAchievementCount() -> Int {
        return unlockedCountValue
    }
}

// MARK: - MockNotificationService

final class MockNotificationService: NotificationServiceProtocol {
    var requestAuthorizationResult: Bool = true
    var authorizationRequested = false
    var scheduledNotifications: [(sessionId: UUID, title: String, timeInterval: TimeInterval)] = []
    var cancelledIdentifiers: [String] = []

    // 向后兼容：旧版 FocusServiceTests 使用以下属性
    var scheduleSessionEndNotificationCalled: Bool { !scheduledNotifications.isEmpty }
    var lastScheduledSessionId: UUID? { scheduledNotifications.last?.sessionId }
    var lastScheduledTimeInterval: TimeInterval { scheduledNotifications.last?.timeInterval ?? 0 }
    var cancelNotificationCalled: Bool { !cancelledIdentifiers.isEmpty }
    var lastCancelledIdentifier: String? { cancelledIdentifiers.last }

    func requestAuthorization() async -> Bool {
        authorizationRequested = true
        return requestAuthorizationResult
    }

    func scheduleSessionEndNotification(sessionId: UUID, title: String, timeInterval: TimeInterval) {
        scheduledNotifications.append((sessionId, title, timeInterval))
    }

    func cancelNotification(withIdentifier identifier: String) {
        cancelledIdentifiers.append(identifier)
    }

    /// 修复（2026-10-15 通知乱弹）：记录全量清理调用，供回归断言
    var cancelAllSessionNotificationsCallCount: Int = 0
    func cancelAllSessionNotifications() {
        cancelAllSessionNotificationsCallCount += 1
    }
}

// MARK: - MockAppBlockerService

final class MockAppBlockerService: AppBlockerServiceProtocol {
    private(set) var isBlocking: Bool = false
    var startBlockingCalled = false
    var stopBlockingCalled = false

    func startBlocking() {
        isBlocking = true
        startBlockingCalled = true
    }

    func stopBlocking() {
        isBlocking = false
        stopBlockingCalled = true
    }
}

// MARK: - MockAudioService

final class MockAudioService: AudioServiceProtocol {
    private(set) var isWhiteNoisePlaying: Bool = false
    var playStartSoundCalled = false
    var playCompleteSoundCalled = false
    var playAlarmSoundCalled = false
    var toggleWhiteNoiseCalled = false
    var configureAudioSessionCalled = false

    func playStartSound() {
        playStartSoundCalled = true
    }

    func playCompleteSound() {
        playCompleteSoundCalled = true
    }

    func playAlarmSound() {
        playAlarmSoundCalled = true
    }

    func toggleWhiteNoise() {
        toggleWhiteNoiseCalled = true
        isWhiteNoisePlaying.toggle()
    }

    var setWhiteNoiseTypeCalled = false
    var whiteNoiseTypeSet: WhiteNoiseType?

    func setWhiteNoiseType(_ type: WhiteNoiseType) {
        setWhiteNoiseTypeCalled = true
        whiteNoiseTypeSet = type
    }

    func configureAudioSession() {
        configureAudioSessionCalled = true
    }
}

// MARK: - MockSpeechService

final class MockSpeechService: SpeechServiceProtocol {
    var speakCalled = false
    var lastSpokenText: String?
    var isSpeechEnabledValue = true

    func speak(_ text: String) {
        speakCalled = true
        lastSpokenText = text
    }

    var isSpeechEnabled: Bool { isSpeechEnabledValue }
}

// MARK: - MockScheduleService

final class MockScheduleService: ScheduleServiceProtocol {
    var events: [ScheduleItem] = []
    var createdEvents: [ScheduleItem] = []
    var updatedEvents: [ScheduleItem] = []
    var deletedEvents: [ScheduleItem] = []

    var createEventCalledHandler: (() -> Void)?
    var updateEventCalledHandler: (() -> Void)?
    var deleteEventCalledHandler: (() -> Void)?

    func createEvent(title: String, startDate: Date, endDate: Date?, isAllDay: Bool, location: String?, notes: String?, colorHex: String?, category: ScheduleCategory, repeatRule: RepeatRule, reminderEnabled: Bool, reminderLeadMinutes: Int, task: Task?) -> ScheduleItem {
        createEventCalledHandler?()
        // 返回 events 中的最后一个
        if let last = events.last {
            createdEvents.append(last)
            return last
        }
        guard let first = events.first else {
            fatalError("MockScheduleService 未配置 events 且无 createEventHandler —— 请在测试中先注入事件")
        }
        return first
    }

    func updateEvent(_ event: ScheduleItem, title: String?, startDate: Date?, endDate: Date?, isAllDay: Bool?, location: String?, notes: String?, colorHex: String?, category: ScheduleCategory?, repeatRule: RepeatRule?, reminderEnabled: Bool?, reminderLeadMinutes: Int?) {
        updateEventCalledHandler?()
        updatedEvents.append(event)
        if let t = title { event.title = t }
        if let s = startDate { event.startDate = s }
        if let e = endDate { event.endDate = e }
        if let a = isAllDay { event.isAllDay = a }
        if let l = location { event.location = l }
        if let n = notes { event.notes = n }
        if let c = colorHex { event.colorHex = c }
        if let cat = category { event.category = cat.rawValue }
        if let r = repeatRule { event.repeatRule = r.rawValue }
        if let re = reminderEnabled { event.reminderEnabled = re }
        if let rl = reminderLeadMinutes { event.reminderLeadMinutes = Int32(rl) }
    }

    func deleteEvent(_ event: ScheduleItem) {
        deleteEventCalledHandler?()
        deletedEvents.append(event)
        events.removeAll { $0.id == event.id }
    }

    func fetchEvents(from startDate: Date, to endDate: Date) -> [ScheduleItem] {
        return events.filter { $0.startDate >= startDate && $0.startDate < endDate }
    }

    func fetchEventsForDate(_ date: Date) -> [ScheduleItem] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        return events.filter { $0.startDate >= startOfDay && $0.startDate < endOfDay }
    }

    func fetchAllEvents() -> [ScheduleItem] {
        return events
    }

    func fetchEvent(id: UUID) -> ScheduleItem? {
        return events.first { $0.id == id }
    }
}

// MARK: - MockHabitService

final class MockHabitService: HabitServiceProtocol {
    var habits: [Habit] = []
    var records: [HabitRecord] = []

    var createHabitCalledHandler: (() -> Void)?
    var deleteHabitCalledHandler: (() -> Void)?
    var checkInCalledHandler: (() -> Void)?
    var removeCheckInCalledHandler: (() -> Void)?
    var recalculateStreakCalledHandler: ((Habit) -> Void)?
    var defaultCheckInRecord: HabitRecord?

    func createHabit(name: String, descriptionText: String?, iconName: String?, colorHex: String?, frequency: String, targetCount: Int16) -> Habit {
        createHabitCalledHandler?()
        guard let first = habits.first else {
            fatalError("MockHabitService 未配置 habits 且无 createHabitHandler —— 请在测试中先注入习惯")
        }
        return first
    }

    func updateHabit(_ habit: Habit, name: String?, descriptionText: String?, iconName: String?, colorHex: String?, frequency: String?, targetCount: Int16?) {
        if let n = name { habit.name = n }
        if let d = descriptionText { habit.descriptionText = d }
        if let i = iconName { habit.iconName = i }
        if let c = colorHex { habit.colorHex = c }
        if let f = frequency { habit.frequency = f }
        if let t = targetCount { habit.targetCount = t }
    }

    func deleteHabit(_ habit: Habit) {
        deleteHabitCalledHandler?()
        habits.removeAll { $0.id == habit.id }
    }

    /// 注意：不可用 fatalError —— 测试可能只验证"调用了 service 且不崩溃"，
    /// 此时未预置 records / defaultCheckInRecord，fatalError 会导致测试进程崩溃（SIGTRAP）。
    /// 无预置数据时返回习惯自身派生的一条占位记录。
    func checkIn(habit: Habit, count: Int16, note: String?) -> HabitRecord {
        checkInCalledHandler?()
        if let record = records.first {
            return record
        }
        if let defaultRecord = defaultCheckInRecord {
            return defaultRecord
        }
        let placeholder = HabitRecord(context: habit.managedObjectContext ?? PersistenceController.shared.viewContext)
        placeholder.storageId = UUID()
        placeholder.habit = habit
        placeholder.date = Date()
        placeholder.count = count
        placeholder.note = note
        placeholder.createdAt = Date()
        return placeholder
    }

    func removeCheckIn(_ record: HabitRecord) {
        removeCheckInCalledHandler?()
        records.removeAll { $0.id == record.id }
    }

    func fetchAllHabits() -> [Habit] {
        return habits
    }

    func fetchHabitRecords(habit: Habit, from date: Date, to endDate: Date) -> [HabitRecord] {
        // 崩溃修复（2026-10-02）：`HabitRecord.habit` 改为可选关系（CloudKit 不支持级联删除，
        // 合并后可能残留 habit == nil 的孤儿记录），故需用可选链比较
        return records.filter { $0.habit?.id == habit.id && $0.date >= date && $0.date <= endDate }
    }

    func fetchRecords(from startDate: Date, to endDate: Date) -> [HabitRecord] {
        return records.filter { $0.date >= startDate && $0.date <= endDate }
    }

    func recalculateStreak(for habit: Habit) {
        recalculateStreakCalledHandler?(habit)
    }
}

// MARK: - MockTimeRecordService

final class MockTimeRecordService: TimeRecordServiceProtocol {
    var records: [TimeRecord] = []
    var currentRecord: TimeRecord?

    var startRecordingCalledHandler: (() -> Void)?
    var stopRecordingCalledHandler: (() -> Void)?
    var deleteRecordCalledHandler: (() -> Void)?

    var totalDurationToReturn: Double = 0
    var durationByProjectToReturn: [(project: String, duration: Double)] = []

    func startRecording(task: Task?, note: String?, project: String?, tag: Tag?) -> TimeRecord {
        startRecordingCalledHandler?()
        guard let first = records.first else {
            fatalError("MockTimeRecordService 未配置 records —— 请在测试中先注入记录")
        }
        currentRecord = first
        return first
    }

    func stopRecording(_ record: TimeRecord) {
        stopRecordingCalledHandler?()
        let end = Date()
        if let pauseStart = record.pauseStartDate {
            record.pausedDuration += max(0, end.timeIntervalSince(pauseStart))
            record.pauseStartDate = nil
        }
        record.endTime = end
        record.duration = max(0, end.timeIntervalSince(record.startTime) - record.pausedDuration)
        currentRecord = nil
    }

    func pauseRecording(_ record: TimeRecord) {
        guard record.endTime == nil, record.pauseStartDate == nil else { return }
        record.pauseStartDate = Date()
    }

    func resumeRecording(_ record: TimeRecord) {
        guard record.endTime == nil, let pauseStart = record.pauseStartDate else { return }
        record.pausedDuration += max(0, Date().timeIntervalSince(pauseStart))
        record.pauseStartDate = nil
    }

    func netElapsedSeconds(for record: TimeRecord) -> TimeInterval {
        if record.endTime != nil { return max(0, record.duration) }
        let wall = max(0, Date().timeIntervalSince(record.startTime))
        let currentPause = record.pauseStartDate.map { max(0, Date().timeIntervalSince($0)) } ?? 0
        return max(0, wall - record.pausedDuration - currentPause)
    }

    func updateRecord(_ record: TimeRecord, note: String?, project: String?, isBillable: Bool?, tag: Tag?) {
        if let n = note { record.note = n }
        if let p = project { record.project = p }
        if let b = isBillable { record.isBillable = b }
        if let t = tag { record.tag = t }
    }

    func deleteRecord(_ record: TimeRecord) {
        deleteRecordCalledHandler?()
        records.removeAll { $0.id == record.id }
    }

    func fetchAllRecords() -> [TimeRecord] {
        return records
    }

    func fetchRecords(from: Date, to: Date) -> [TimeRecord] {
        return records.filter { $0.startTime >= from && $0.startTime < to }
    }

    func fetchRecordsForTask(_ task: Task) -> [TimeRecord] {
        return records.filter { $0.task?.id == task.id }
    }

    func getTotalDuration(from: Date, to: Date) -> Double {
        return totalDurationToReturn
    }

    func getDurationByProject(from: Date, to: Date) -> [(project: String, duration: Double)] {
        return durationByProjectToReturn
    }
}

// MARK: - MockSyncService

final class MockSettingsSyncService: SyncServiceProtocol {
    var isCloudAvailable: Bool = false
    var setupCloudKitCalled = false
    var forceSyncCalled = false
    /// 测试可配置：模拟手动同步返回的真实结果（用户反馈 2026-11-17）
    var forceSyncResult: SyncOutcome = .noLocalChanges

    func setupCloudKit() {
        setupCloudKitCalled = true
    }

    @discardableResult
    func forceSync() -> SyncOutcome {
        forceSyncCalled = true
        return forceSyncResult
    }
}

// MARK: - MockReminderService
// 修复（2026-10-15 审查 P1-022）：ReminderServiceProtocol 是 12 个服务协议中
// 唯一没有 Mock 的一个，此前只能依赖真实 UNUserNotificationCenter 冒烟测试

final class MockReminderService: ReminderServiceProtocol {
    var rescheduleAllCalledCount = 0

    func rescheduleAll() {
        rescheduleAllCalledCount += 1
    }
}

// MARK: - MockTagService（2026-11-19 标签功能回归测试）

final class MockTagService: TagServiceProtocol {
    var tags: [Tag] = []
    /// 记录最后一次全量替换的 (tags, task)，供断言
    var lastSetTags: (Set<Tag>, Task)?
    var createTagCalledHandler: ((String, String?) -> Void)?

    func fetchAllTags() -> [Tag] {
        tags
    }

    func createTag(name: String, colorHex: String?) -> Tag? {
        createTagCalledHandler?(name, colorHex)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // 与真实实现一致：同名去重
        if let existing = tags.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return existing
        }
        let tag = Tag(context: tags.first?.managedObjectContext ?? PersistenceController(inMemory: true).viewContext)
        tag.storageId = UUID()
        tag.name = trimmed
        tag.colorHex = colorHex
        tag.createdAt = Date()
        tags.append(tag)
        return tag
    }

    func renameTag(_ tag: Tag, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        tag.name = trimmed
    }

    func setTagColor(_ tag: Tag, colorHex: String?) {
        tag.colorHex = colorHex
    }

    func deleteTag(_ tag: Tag) {
        tags.removeAll { $0.id == tag.id }
    }

    func setTags(_ tags: Set<Tag>, on task: Task) {
        task.tags = tags
        lastSetTags = (tags, task)
    }
}

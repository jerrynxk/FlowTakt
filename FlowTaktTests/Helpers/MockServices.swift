import Foundation
import CoreData
@testable import FlowTakt

// MARK: - Mock Service 实现
// 这些 Mock 用于 ViewModel 测试，避免真实 CoreData 和系统 API 依赖
// 所有 Mock 严格 conform 到对应的真实协议

// MARK: - MockFocusService

final class MockFocusService: FocusServiceProtocol {
    private static let testController = PersistenceController(inMemory: true)
    var sessions: [FocusSession] = []

    // Handler closures
    var startFocusSessionHandler: ((Task?, TimeInterval, FocusPhase, Int16) -> FocusSession)?
    var completeSessionHandler: ((FocusSession) -> Void)?
    var interruptSessionHandler: ((FocusSession) -> Void)?
    var abandonSessionHandler: ((FocusSession) -> Void)?

    // Configurable results
    var getCurrentSessionResult: FocusSession?
    var fetchTodaysSessionsResult: [FocusSession] = []

    // MARK: - FocusServiceProtocol

    func startFocusSession(task: Task?, plannedDuration: TimeInterval, phase: FocusPhase, roundIndex: Int16) -> FocusSession {
        if let handler = startFocusSessionHandler {
            return handler(task, plannedDuration, phase, roundIndex)
        }
        // 返回一个默认的 session 实例，而不是 fatalError，避免测试进程崩溃
        let session = FocusSession(context: Self.testController.viewContext)
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
        sessions.append(session)
        return session
    }

    func completeSession(_ session: FocusSession) {
        completeSessionHandler?(session)
    }

    func interruptSession(_ session: FocusSession) {
        interruptSessionHandler?(session)
    }

    func abandonSession(_ session: FocusSession) {
        abandonSessionHandler?(session)
    }

    func getCurrentSession() -> FocusSession? {
        return getCurrentSessionResult
    }

    func fetchTodaysSessions() -> [FocusSession] {
        return fetchTodaysSessionsResult
    }
}

// MARK: - MockTaskService

final class MockTaskService: TaskServiceProtocol {
    private static let testController = PersistenceController(inMemory: true)
    var tasks: [Task] = []

    // Handler closures（签名与真实协议完全一致，包含 recurrenceRule）
    var createTaskHandler: ((String, String?, Int16, Int16, Date?, String?) -> Task)?
    var updateTaskHandler: ((Task, String?, String?, Int16?, Int16?, String?, Date?, String?) -> Void)?
    var deleteTaskHandler: ((Task) -> Void)?
    var incrementCompletedPomodorosHandler: ((Task) -> Void)?

    // Tracking
    var createTaskCallCount = 0
    var updateTaskCallCount = 0
    var deleteTaskCallCount = 0
    var incrementCompletedPomodorosCallCount = 0
    /// 最近一次 createTask 传入的 recurrenceRule（便于测试断言）
    var lastCreateTaskRecurrenceRule: String?
    /// 最近一次 updateTask 传入的 recurrenceRule
    var lastUpdateTaskRecurrenceRule: String?

    // MARK: - TaskServiceProtocol

    func createTask(title: String, notes: String?, estimatedPomodoros: Int16, priority: Int16, dueDate: Date?, recurrenceRule: String?) -> Task {
        createTaskCallCount += 1
        lastCreateTaskRecurrenceRule = recurrenceRule
        if let handler = createTaskHandler {
            return handler(title, notes, estimatedPomodoros, priority, dueDate, recurrenceRule)
        }
        // 返回一个默认的 task 实例，而不是 fatalError
        let task = Task(context: Self.testController.viewContext)
        task.id = UUID()
        task.title = title
        task.notes = notes
        task.estimatedPomodoros = estimatedPomodoros
        task.completedPomodoros = 0
        task.priority = priority
        task.status = TaskStatus.active.rawValue
        task.dueDate = dueDate
        if let rule = recurrenceRule, rule != "none" {
            task.isRecurring = true
            task.recurrenceRule = rule
        }
        task.displayOrder = Int16(tasks.count)
        task.createdAt = Date()
        task.updatedAt = Date()
        tasks.append(task)
        return task
    }

    func updateTask(_ task: Task, title: String?, notes: String?, estimatedPomodoros: Int16?, priority: Int16?, status: String?, dueDate: Date?, recurrenceRule: String?) {
        updateTaskCallCount += 1
        lastUpdateTaskRecurrenceRule = recurrenceRule
        updateTaskHandler?(task, title, notes, estimatedPomodoros, priority, status, dueDate, recurrenceRule)
    }

    func deleteTask(_ task: Task) {
        deleteTaskCallCount += 1
        deleteTaskHandler?(task)
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

    func incrementCompletedPomodoros(for task: Task) {
        incrementCompletedPomodorosCallCount += 1
        incrementCompletedPomodorosHandler?(task)
    }
}

// MARK: - MockAchievementService

final class MockAchievementService: AchievementServiceProtocol {
    var achievements: [Achievement] = []
    var totalPoints: Int = 0
    var todaysPoints: Int = 0
    var unlockedAchievementCount: Int = 0

    // Tracking
    var checkAndUnlockAchievementsCalled = false
    var checkAndUnlockAchievementsCallCount = 0
    var checkAndUnlockAchievementsHandler: (() -> Void)?
    var newlyUnlockedAchievements: [Achievement] = []

    // MARK: - AchievementServiceProtocol

    func checkAndUnlockAchievements() {
        checkAndUnlockAchievementsCalled = true
        checkAndUnlockAchievementsCallCount += 1
        checkAndUnlockAchievementsHandler?()
    }

    func fetchAllAchievements() -> [Achievement] {
        return achievements
    }

    func getTotalPoints() -> Int {
        return totalPoints
    }

    func getTodaysPoints() -> Int {
        return todaysPoints
    }

    func getUnlockedAchievementCount() -> Int {
        return unlockedAchievementCount
    }
}

// MARK: - MockNotificationService

final class MockNotificationService: NotificationServiceProtocol {
    var requestAuthorizationResult: Bool = true

    // Tracking
    var scheduleSessionEndNotificationCalled = false
    var lastScheduledSessionId: UUID?
    var lastScheduledTitle: String?
    var lastScheduledTimeInterval: TimeInterval = 0

    var cancelNotificationCalled = false
    var lastCancelledIdentifier: String?

    // MARK: - NotificationServiceProtocol

    func requestAuthorization() async -> Bool {
        return requestAuthorizationResult
    }

    func scheduleSessionEndNotification(sessionId: UUID, title: String, timeInterval: TimeInterval) {
        scheduleSessionEndNotificationCalled = true
        lastScheduledSessionId = sessionId
        lastScheduledTitle = title
        lastScheduledTimeInterval = timeInterval
    }

    func cancelNotification(withIdentifier identifier: String) {
        cancelNotificationCalled = true
        lastCancelledIdentifier = identifier
    }
}

// MARK: - MockAppBlockerService

final class MockAppBlockerService: AppBlockerServiceProtocol {
    var isBlocking: Bool = false

    // Tracking
    var startBlockingCalled = false
    var stopBlockingCalled = false

    // MARK: - AppBlockerServiceProtocol

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
    var isWhiteNoisePlaying: Bool = false

    // Tracking
    var playStartSoundCalled = false
    var playCompleteSoundCalled = false
    var playAlarmSoundCalled = false
    var toggleWhiteNoiseCalled = false
    var configureAudioSessionCalled = false

    // MARK: - AudioServiceProtocol

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

    func configureAudioSession() {
        configureAudioSessionCalled = true
    }
}

import Foundation
import CoreData
@testable import FlowTakt

// MARK: - Mock Service 实现
// 这些 Mock 用于 ViewModel 测试，避免真实 CoreData 和系统 API 依赖
// 所有 Mock 严格 conform 到对应的真实协议

// MARK: - MockFocusService

final class MockFocusService: FocusServiceProtocol {
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
        fatalError("MockFocusService.startFocusSessionHandler 未设置")
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
    var tasks: [Task] = []

    // Handler closures
    var createTaskHandler: ((String, String?, Int16, Int16, Date?) -> Task)?
    var updateTaskHandler: ((Task, String?, String?, Int16?, Int16?, String?, Date?) -> Void)?
    var deleteTaskHandler: ((Task) -> Void)?
    var incrementCompletedPomodorosHandler: ((Task) -> Void)?

    // Tracking
    var createTaskCallCount = 0
    var updateTaskCallCount = 0
    var deleteTaskCallCount = 0
    var incrementCompletedPomodorosCallCount = 0

    // MARK: - TaskServiceProtocol

    func createTask(title: String, notes: String?, estimatedPomodoros: Int16, priority: Int16, dueDate: Date?) -> Task {
        createTaskCallCount += 1
        if let handler = createTaskHandler {
            return handler(title, notes, estimatedPomodoros, priority, dueDate)
        }
        fatalError("MockTaskService.createTaskHandler 未设置")
    }

    func updateTask(_ task: Task, title: String?, notes: String?, estimatedPomodoros: Int16?, priority: Int16?, status: String?, dueDate: Date?) {
        updateTaskCallCount += 1
        updateTaskHandler?(task, title, notes, estimatedPomodoros, priority, status, dueDate)
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

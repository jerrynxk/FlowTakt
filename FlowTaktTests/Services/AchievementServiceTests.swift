import XCTest
import CoreData
@testable import FlowTakt

// MARK: - AchievementServiceTests
// 测试 AchievementService：成就获取、积分计算、成就解锁、今日积分

@MainActor
final class AchievementServiceTests: XCTestCase {
    var persistence: PersistenceController!
    var mockFocusService: MockFocusService!
    var achievementService: AchievementService!

    override func setUp() {
        super.setUp()
        persistence = PersistenceController(inMemory: true)
        mockFocusService = MockFocusService()
        achievementService = AchievementService(
            persistenceController: persistence,
            focusService: mockFocusService
        )
    }

    override func tearDown() {
        achievementService = nil
        mockFocusService = nil
        persistence = nil
        super.tearDown()
    }

    // ========================================================================
    // MARK: - 成就默认初始化
    // ========================================================================

    func testFetchAllAchievements_WhenFirstCalled_CreatesAllDefaultAchievements() {
        // When
        let allAchievements = achievementService.fetchAllAchievements()

        // Then
        XCTAssertEqual(allAchievements.count, AppConstants.achievements.count,
                       "应创建全部 \(AppConstants.achievements.count) 个默认成就")
    }

    func testFetchAllAchievements_WhenCalledTwice_DoesNotDuplicate() {
        // Given
        _ = achievementService.fetchAllAchievements()

        // When
        let allAchievements = achievementService.fetchAllAchievements()

        // Then
        XCTAssertEqual(allAchievements.count, AppConstants.achievements.count,
                       "第二次调用不应重复创建")
    }

    func testFetchAllAchievements_InitiallyAllLocked() {
        // When
        let allAchievements = achievementService.fetchAllAchievements()

        // Then
        for achievement in allAchievements {
            XCTAssertFalse(achievement.isUnlocked, "初始状态所有成就应为未解锁: \(achievement.identifier)")
        }
    }

    func testFetchAllAchievements_HasCorrectIdentifiers() {
        // When
        let allAchievements = achievementService.fetchAllAchievements()
        let identifiers = Set(allAchievements.map { $0.identifier })

        // Then
        XCTAssertTrue(identifiers.contains("first_pomodoro"))
        XCTAssertTrue(identifiers.contains("pomodoros_10"))
        XCTAssertTrue(identifiers.contains("pomodoros_50"))
        XCTAssertTrue(identifiers.contains("pomodoros_100"))
        XCTAssertTrue(identifiers.contains("streak_3"))
        XCTAssertTrue(identifiers.contains("streak_7"))
        XCTAssertTrue(identifiers.contains("streak_30"))
        XCTAssertTrue(identifiers.contains("points_100"))
        XCTAssertTrue(identifiers.contains("points_500"))
        XCTAssertTrue(identifiers.contains("points_1000"))
    }

    // ========================================================================
    // MARK: - 总积分
    // ========================================================================

    func testGetTotalPoints_WhenNoCompletedSessions_ThenReturnsZero() {
        // When
        let total = achievementService.getTotalPoints()

        // Then
        XCTAssertEqual(total, 0)
    }

    func testGetTotalPoints_WhenCompletedSessionsExist_ThenReturnsSum() {
        // Given - 创建已完成会话
        let context = persistence.viewContext
        let session = FocusSession(context: context)
        session.id = UUID()
        session.startTime = Date()
        session.endTime = Date()
        session.plannedDuration = 1500
        session.actualDuration = 1500
        session.phase = FocusPhase.focus.rawValue
        session.roundIndex = 1
        session.status = SessionStatus.completed.rawValue
        session.earnedPoints = 10
        session.createdAt = Date()
        session.updatedAt = Date()
        try? context.save()

        // When
        let total = achievementService.getTotalPoints()

        // Then
        XCTAssertEqual(total, 10)
    }

    // ========================================================================
    // MARK: - 今日积分
    // ========================================================================

    func testGetTodaysPoints_WhenNoSessions_ThenReturnsZero() {
        // When
        let todayPoints = achievementService.getTodaysPoints()

        // Then
        XCTAssertEqual(todayPoints, 0)
    }

    func testGetTodaysPoints_WhenCompletedSessionToday_ThenReturnsPoints() {
        // Given
        let context = persistence.viewContext
        let session = FocusSession(context: context)
        session.id = UUID()
        session.startTime = Date()
        session.endTime = Date()
        session.plannedDuration = 1500
        session.actualDuration = 1500
        session.phase = FocusPhase.focus.rawValue
        session.roundIndex = 1
        session.status = SessionStatus.completed.rawValue
        session.earnedPoints = 10
        session.createdAt = Date()
        session.updatedAt = Date()
        try? context.save()

        // When
        let todayPoints = achievementService.getTodaysPoints()

        // Then
        XCTAssertEqual(todayPoints, 10)
    }

    // ========================================================================
    // MARK: - 已解锁成就计数
    // ========================================================================

    func testGetUnlockedAchievementCount_InitiallyReturnsZero() {
        // When
        let count = achievementService.getUnlockedAchievementCount()

        // Then
        XCTAssertEqual(count, 0)
    }

    func testGetUnlockedAchievementCount_AfterUnlock_ReturnsCorrectCount() {
        // Given - 手动解锁一个成就
        _ = achievementService.fetchAllAchievements()
        let context = persistence.viewContext
        let allAchs = achievementService.fetchAllAchievements()
        if let first = allAchs.first {
            first.isUnlocked = true
            try? context.save()
        }

        // When
        let count = achievementService.getUnlockedAchievementCount()

        // Then
        XCTAssertEqual(count, 1)
    }

    // ========================================================================
    // MARK: - 成就检查与解锁
    // ========================================================================

    func testCheckAndUnlockAchievements_GivenFirstPomodoro_ThenFirstPomodoroAchievementUnlocks() {
        // Given - 播种成就 + 创建 1 个完成番茄
        _ = achievementService.fetchAllAchievements()

        let context = persistence.viewContext
        let session = FocusSession(context: context)
        session.id = UUID()
        session.startTime = Date()
        session.endTime = Date()
        session.plannedDuration = 1500
        session.actualDuration = 1500
        session.phase = FocusPhase.focus.rawValue
        session.roundIndex = 1
        session.status = SessionStatus.completed.rawValue
        session.earnedPoints = 10
        session.createdAt = Date()
        session.updatedAt = Date()
        try? context.save()

        // When
        achievementService.checkAndUnlockAchievements()

        // Then
        let allAchs = achievementService.fetchAllAchievements()
        let firstPomodoro = allAchs.first { $0.identifier == "first_pomodoro" }
        XCTAssertNotNil(firstPomodoro)
        XCTAssertTrue(firstPomodoro?.isUnlocked ?? false, "完成 1 个番茄钟应解锁 '初次专注' 成就")
    }

    func testCheckAndUnlockAchievements_Given10Pomodoros_ThenPomodoros10Unlocks() {
        // Given
        _ = achievementService.fetchAllAchievements()
        let context = persistence.viewContext

        // 创建 10 个已完成会话
        for i in 0..<10 {
            let session = FocusSession(context: context)
            session.id = UUID()
            session.startTime = Date().addingTimeInterval(TimeInterval(-3600 + i * 60))
            session.endTime = Date()
            session.plannedDuration = 1500
            session.actualDuration = 1500
            session.phase = FocusPhase.focus.rawValue
            session.roundIndex = Int16(i + 1)
            session.status = SessionStatus.completed.rawValue
            session.earnedPoints = 10
            session.createdAt = Date()
            session.updatedAt = Date()
        }
        try? context.save()

        // When
        achievementService.checkAndUnlockAchievements()

        // Then
        let allAchs = achievementService.fetchAllAchievements()
        let pomodoro10 = allAchs.first { $0.identifier == "pomodoros_10" }
        XCTAssertNotNil(pomodoro10)
        XCTAssertTrue(pomodoro10?.isUnlocked ?? false, "10 个番茄钟应解锁 '专注新手' 成就")
    }

    func testCheckAndUnlockAchievements_GivenNoCompletedSessions_ThenNoAchievementsUnlock() {
        // Given
        _ = achievementService.fetchAllAchievements()

        // When
        achievementService.checkAndUnlockAchievements()

        // Then
        let unlockedCount = achievementService.getUnlockedAchievementCount()
        XCTAssertEqual(unlockedCount, 0, "无完成会话时不应解锁任何成就")
    }

    func testCheckAndUnlockAchievements_GivenAlreadyUnlocked_DoesNotUnlockAgain() {
        // Given - 先解锁一次
        _ = achievementService.fetchAllAchievements()
        let context = persistence.viewContext
        let session = FocusSession(context: context)
        session.id = UUID()
        session.startTime = Date()
        session.endTime = Date()
        session.plannedDuration = 1500
        session.actualDuration = 1500
        session.phase = FocusPhase.focus.rawValue
        session.roundIndex = 1
        session.status = SessionStatus.completed.rawValue
        session.earnedPoints = 10
        session.createdAt = Date()
        session.updatedAt = Date()
        try? context.save()

        achievementService.checkAndUnlockAchievements()
        let firstUnlockCount = achievementService.getUnlockedAchievementCount()
        XCTAssertGreaterThan(firstUnlockCount, 0, "首次应解锁成就")

        // When - 再次检查（状态未变）
        achievementService.checkAndUnlockAchievements()

        // Then - 解锁数不变
        let secondUnlockCount = achievementService.getUnlockedAchievementCount()
        XCTAssertEqual(secondUnlockCount, firstUnlockCount, "重复检查不应改变解锁数")
    }

    func testCheckAndUnlockAchievements_Given100Points_ThenPoints100Unlocks() {
        // Given
        _ = achievementService.fetchAllAchievements()
        let context = persistence.viewContext

        // 创建 10 个已完成会话，每个 10 分，累计 100 分
        for i in 0..<10 {
            let session = FocusSession(context: context)
            session.id = UUID()
            session.startTime = Date().addingTimeInterval(TimeInterval(-3600 + i * 60))
            session.endTime = Date()
            session.plannedDuration = 1500
            session.actualDuration = 1500
            session.phase = FocusPhase.focus.rawValue
            session.roundIndex = Int16(i + 1)
            session.status = SessionStatus.completed.rawValue
            session.earnedPoints = 10
            session.createdAt = Date()
            session.updatedAt = Date()
        }
        try? context.save()

        // When
        achievementService.checkAndUnlockAchievements()

        // Then
        let allAchs = achievementService.fetchAllAchievements()
        let points100 = allAchs.first { $0.identifier == "points_100" }
        XCTAssertNotNil(points100)
        XCTAssertTrue(points100?.isUnlocked ?? false, "100 积分应解锁 '积分新星' 成就")
    }

    // ========================================================================
    // MARK: - 边界条件
    // ========================================================================

    func testCheckAndUnlockAchievements_WithStreak30Days_ThenStreak30Unlocks() {
        // Given - 创建 30 个在不同日期的已完成会话
        _ = achievementService.fetchAllAchievements()
        let context = persistence.viewContext
        let calendar = Calendar.current

        for i in 0..<30 {
            let session = FocusSession(context: context)
            session.id = UUID()
            let pastDate = calendar.date(byAdding: .day, value: -i, to: Date().startOfDay) ?? Date()
            session.startTime = pastDate
            session.endTime = pastDate.addingTimeInterval(1500)
            session.plannedDuration = 1500
            session.actualDuration = 1500
            session.phase = FocusPhase.focus.rawValue
            session.roundIndex = 1
            session.status = SessionStatus.completed.rawValue
            session.earnedPoints = 10
            session.createdAt = pastDate
            session.updatedAt = pastDate
        }
        try? context.save()

        // When
        achievementService.checkAndUnlockAchievements()

        // Then
        let allAchs = achievementService.fetchAllAchievements()
        let streak30 = allAchs.first { $0.identifier == "streak_30" }
        XCTAssertNotNil(streak30)
        XCTAssertTrue(streak30?.isUnlocked ?? false, "连续 30 天应解锁 '月度坚持' 成就")
    }

    func testCheckAndUnlockAchievements_WithDeletedAchievement_ThenDoesNotCrash() {
        // Given
        _ = achievementService.fetchAllAchievements()
        let allAchs = achievementService.fetchAllAchievements()
        if let first = allAchs.first {
            let context = persistence.viewContext
            context.delete(first)
            try? context.save()
        }

        let context = persistence.viewContext
        let session = FocusSession(context: context)
        session.id = UUID()
        session.startTime = Date()
        session.endTime = Date()
        session.plannedDuration = 1500
        session.actualDuration = 1500
        session.phase = FocusPhase.focus.rawValue
        session.roundIndex = 1
        session.status = SessionStatus.completed.rawValue
        session.earnedPoints = 10
        session.createdAt = Date()
        session.updatedAt = Date()
        try? context.save()

        // When / Then
        achievementService.checkAndUnlockAchievements()
        XCTAssertTrue(true, "部分成就删除后 checkAndUnlockAchievements 不应崩溃")
    }

    func testGetTotalPoints_WithMultipleSessions_ReturnsCorrectSum() {
        // Given
        let context = persistence.viewContext
        for i in 0..<3 {
            let session = FocusSession(context: context)
            session.id = UUID()
            session.startTime = Date()
            session.endTime = Date()
            session.plannedDuration = 1500
            session.actualDuration = 1500
            session.phase = FocusPhase.focus.rawValue
            session.roundIndex = Int16(i + 1)
            session.status = SessionStatus.completed.rawValue
            session.earnedPoints = 10
            session.createdAt = Date()
            session.updatedAt = Date()
        }
        try? context.save()

        // When
        let total = achievementService.getTotalPoints()

        // Then
        XCTAssertEqual(total, 30)
    }
}

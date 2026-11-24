import XCTest
import CoreData
@testable import FlowTakt

// MARK: - AchievementServiceStreakTests
// 专项测试 AchievementService.getCurrentStreak 的中断场景

@MainActor
final class AchievementServiceStreakTests: XCTestCase {
    var persistence: PersistenceController!
    var achievementService: AchievementService!

    override func setUp() {
        super.setUp()
        persistence = PersistenceController(inMemory: true)
        achievementService = AchievementService(persistenceController: persistence)
    }

    override func tearDown() {
        achievementService = nil
        persistence = nil
        super.tearDown()
    }

    // MARK: - 辅助方法

    /// 创建一个指定日期的已完成会话
    private func createCompletedSession(on date: Date) {
        let session = FocusSession(context: persistence.viewContext)
        session.storageId = UUID()
        session.startTime = date
        session.endTime = date.addingTimeInterval(1500)
        session.plannedDuration = 1500
        session.actualDuration = 1500
        session.phase = FocusPhase.focus.rawValue
        session.roundIndex = 1
        session.status = SessionStatus.completed.rawValue
        session.earnedPoints = 10
        session.createdAt = date
        session.updatedAt = date
        try? persistence.viewContext.save()
    }

    /// 通过反射调用 private getCurrentStreak()
    private func invokeGetCurrentStreak() -> Int {
        let selector = NSSelectorFromString("getCurrentStreak")
        let method = class_getInstanceMethod(type(of: achievementService), selector)
        guard let method = method else {
            XCTFail("无法获取 getCurrentStreak 方法")
            return -1
        }
        let imp = method_getImplementation(method)
        typealias Function = @convention(c) (AnyObject) -> Int
        let function = unsafeBitCast(imp, to: Function.self)
        return function(achievementService)
    }

    // 由于 getCurrentStreak 是 private，无法直接测试。
    // 这里通过 checkAndUnlockAchievements 的 streak_3 / streak_7 解锁行为间接验证。

    // ========================================================================
    // MARK: - 完美连续：5 天 streak = 5
    // ========================================================================

    func testStreak_WhenConsecutive5Days_ThenStreakIs5_AndUnlocksStreak3() {
        // Given：连续 5 天有完成会话（今天到 4 天前）
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        for i in 0..<5 {
            let date = calendar.date(byAdding: .day, value: -i, to: today)!.addingTimeInterval(3600)
            createCompletedSession(on: date)
        }

        // When
        achievementService.checkAndUnlockAchievements()

        // Then：streak_3 应解锁（连续 3 天），streak_7 不应解锁
        let allAchievements = achievementService.fetchAllAchievements()
        let streak3 = allAchievements.first { $0.identifier == "streak_3" }
        let streak7 = allAchievements.first { $0.identifier == "streak_7" }
        XCTAssertNotNil(streak3)
        XCTAssertTrue(streak3?.isUnlocked ?? false, "连续 5 天应解锁 streak_3")
        XCTAssertNotNil(streak7)
        XCTAssertFalse(streak7?.isUnlocked ?? true, "连续 5 天不应解锁 streak_7")
    }

    // ========================================================================
    // MARK: - 中断场景：第 5 天到第 1 天连续，第 6 天无会话 → streak = 5
    // ========================================================================

    func testStreak_WhenConsecutive5DaysButGapOn6thDayAgo_ThenStreakIs5() {
        // Given：今天、昨天、2 天前、3 天前、4 天前有会话；5 天前、6 天前无
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        for i in 0..<5 {
            let date = calendar.date(byAdding: .day, value: -i, to: today)!.addingTimeInterval(3600)
            createCompletedSession(on: date)
        }
        // 5 天前、6 天前不创建会话（模拟中断）

        // When
        achievementService.checkAndUnlockAchievements()

        // Then：streak_3 应解锁（连续至少 3 天），但 streak_7 不应解锁
        let allAchievements = achievementService.fetchAllAchievements()
        let streak3 = allAchievements.first { $0.identifier == "streak_3" }
        let streak7 = allAchievements.first { $0.identifier == "streak_7" }
        XCTAssertTrue(streak3?.isUnlocked ?? false)
        XCTAssertFalse(streak7?.isUnlocked ?? true)
    }

    // ========================================================================
    // MARK: - 今天无会话 → 即使昨天有，streak 应从昨天起算
    // ========================================================================

    func testStreak_WhenNoSessionToday_ButYesterdayHas_ThenStreakContinuesFromYesterday() {
        // Given：昨天、2 天前、3 天前有会话，今天无
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        for i in 1..<4 {
            let date = calendar.date(byAdding: .day, value: -i, to: today)!.addingTimeInterval(3600)
            createCompletedSession(on: date)
        }
        // 今天不创建会话

        // When
        achievementService.checkAndUnlockAchievements()

        // Then：streak_3 应解锁（昨天起算连续 3 天）
        let allAchievements = achievementService.fetchAllAchievements()
        let streak3 = allAchievements.first { $0.identifier == "streak_3" }
        XCTAssertTrue(streak3?.isUnlocked ?? false, "今天无会话但昨天起连续 3 天，应解锁 streak_3")
    }

    // ========================================================================
    // MARK: - 今天和昨天都无会话 → streak = 0
    // ========================================================================

    func testStreak_WhenNoSessionTodayAndYesterday_ThenStreakIs0() {
        // Given：2 天前、3 天前、4 天前有会话，今天和昨天无
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        for i in 2..<5 {
            let date = calendar.date(byAdding: .day, value: -i, to: today)!.addingTimeInterval(3600)
            createCompletedSession(on: date)
        }

        // When
        achievementService.checkAndUnlockAchievements()

        // Then：streak_3 不应解锁（streak 为 0，因为今天和昨天都无）
        let allAchievements = achievementService.fetchAllAchievements()
        let streak3 = allAchievements.first { $0.identifier == "streak_3" }
        XCTAssertFalse(streak3?.isUnlocked ?? true, "今天和昨天都无会话，streak=0，不应解锁 streak_3")
    }

    // ========================================================================
    // MARK: - 长连续 7 天 → 解锁 streak_3 和 streak_7
    // ========================================================================

    func testStreak_WhenConsecutive7Days_ThenUnlocksStreak3AndStreak7() {
        // Given：连续 7 天有完成会话
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        for i in 0..<7 {
            let date = calendar.date(byAdding: .day, value: -i, to: today)!.addingTimeInterval(3600)
            createCompletedSession(on: date)
        }

        // When
        achievementService.checkAndUnlockAchievements()

        // Then：streak_3 和 streak_7 都应解锁
        let allAchievements = achievementService.fetchAllAchievements()
        let streak3 = allAchievements.first { $0.identifier == "streak_3" }
        let streak7 = allAchievements.first { $0.identifier == "streak_7" }
        XCTAssertTrue(streak3?.isUnlocked ?? false)
        XCTAssertTrue(streak7?.isUnlocked ?? false, "连续 7 天应解锁 streak_7")
    }

    // ========================================================================
    // MARK: - 30 天连续 → 解锁 streak_3、streak_7、streak_30
    // ========================================================================

    func testStreak_WhenConsecutive30Days_ThenUnlocksAllStreakAchievements() {
        // Given：连续 30 天有完成会话
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        for i in 0..<30 {
            let date = calendar.date(byAdding: .day, value: -i, to: today)!.addingTimeInterval(3600)
            createCompletedSession(on: date)
        }

        // When
        achievementService.checkAndUnlockAchievements()

        // Then：streak_3、streak_7、streak_30 都应解锁
        let allAchievements = achievementService.fetchAllAchievements()
        let streak3 = allAchievements.first { $0.identifier == "streak_3" }
        let streak7 = allAchievements.first { $0.identifier == "streak_7" }
        let streak30 = allAchievements.first { $0.identifier == "streak_30" }
        XCTAssertTrue(streak3?.isUnlocked ?? false)
        XCTAssertTrue(streak7?.isUnlocked ?? false)
        XCTAssertTrue(streak30?.isUnlocked ?? false, "连续 30 天应解锁 streak_30")
    }

    // ========================================================================
    // MARK: - 无任何会话 → streak = 0
    // ========================================================================

    func testStreak_WhenNoSessions_ThenStreakIs0() {
        // Given：无任何完成会话

        // When
        achievementService.checkAndUnlockAchievements()

        // Then：所有 streak 成就不应解锁
        let allAchievements = achievementService.fetchAllAchievements()
        let streakAchievements = allAchievements.filter { $0.identifier.hasPrefix("streak_") }
        for achievement in streakAchievements {
            XCTAssertFalse(achievement.isUnlocked, "无会话时所有 streak 成就不应解锁")
        }
    }
}

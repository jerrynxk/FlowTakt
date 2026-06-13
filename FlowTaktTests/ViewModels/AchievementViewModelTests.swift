import XCTest
import Combine
@testable import FlowTakt

// MARK: - AchievementViewModelTests
// 测试 AchievementViewModel：成就列表展示、积分显示、刷新

@MainActor
final class AchievementViewModelTests: XCTestCase {
    var mockAchievementService: MockAchievementService!
    var viewModel: AchievementViewModel!
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        mockAchievementService = MockAchievementService()
        viewModel = AchievementViewModel(achievementService: mockAchievementService)
        cancellables = Set<AnyCancellable>()
    }

    override func tearDown() {
        viewModel = nil
        mockAchievementService = nil
        cancellables = nil
        super.tearDown()
    }

    // ========================================================================
    // MARK: - 初始状态
    // ========================================================================

    func testInitialState_WhenCreated_ThenCallsRefresh() {
        // Then
        XCTAssertTrue(viewModel.achievements.isEmpty, "无预设成就时应为空")
        XCTAssertEqual(viewModel.totalPoints, 0)
        XCTAssertEqual(viewModel.unlockedCount, 0)
        XCTAssertEqual(viewModel.todayPoints, 0)
    }

    // ========================================================================
    // MARK: - 刷新
    // ========================================================================

    func testRefresh_WhenAchievementsExist_ThenUpdatesAllData() {
        // Given
        mockAchievementService.totalPoints = 50
        mockAchievementService.todaysPoints = 10
        mockAchievementService.unlockedAchievementCount = 3

        // When
        viewModel.refresh()

        // Then
        XCTAssertEqual(viewModel.totalPoints, 50)
        XCTAssertEqual(viewModel.todayPoints, 10)
        XCTAssertEqual(viewModel.unlockedCount, 3)
    }

    func testRefresh_WithZeroValues_ThenAllZero() {
        // Given
        mockAchievementService.totalPoints = 0
        mockAchievementService.todaysPoints = 0
        mockAchievementService.unlockedAchievementCount = 0

        // When
        viewModel.refresh()

        // Then
        XCTAssertEqual(viewModel.totalPoints, 0)
        XCTAssertEqual(viewModel.todayPoints, 0)
        XCTAssertEqual(viewModel.unlockedCount, 0)
    }

    // ========================================================================
    // MARK: - 积分为 0
    // ========================================================================

    func testTotalPoints_InitiallyZero() {
        XCTAssertEqual(viewModel.totalPoints, 0)
    }

    func testTodayPoints_InitiallyZero() {
        XCTAssertEqual(viewModel.todayPoints, 0)
    }

    func testUnlockedCount_InitiallyZero() {
        XCTAssertEqual(viewModel.unlockedCount, 0)
    }

    // ========================================================================
    // MARK: - Published 属性变化
    // ========================================================================

    func testPublishedTotalPoints_WhenRefreshed_ThenPublishesUpdate() {
        // Given
        mockAchievementService.totalPoints = 100
        let expectation = expectation(description: "等待 totalPoints 发布")

        viewModel.$totalPoints
            .dropFirst()
            .sink { value in
                if value == 100 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        viewModel.refresh()

        // Then
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(viewModel.totalPoints, 100)
    }

    func testPublishedUnlockedCount_WhenRefreshed_ThenPublishesUpdate() {
        // Given
        mockAchievementService.unlockedAchievementCount = 5
        let expectation = expectation(description: "等待 unlockedCount 发布")

        viewModel.$unlockedCount
            .dropFirst()
            .sink { value in
                if value == 5 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        viewModel.refresh()

        // Then
        wait(for: [expectation], timeout: 1.0)
    }

    // ========================================================================
    // MARK: - 边界条件
    // ========================================================================

    func testRefresh_WithZeroTotalPoints_ThenTotalPointsIsZero() {
        // Given
        mockAchievementService.totalPoints = 0
        mockAchievementService.todaysPoints = 0
        mockAchievementService.unlockedAchievementCount = 0

        // When
        viewModel.refresh()

        // Then
        XCTAssertEqual(viewModel.totalPoints, 0)
        XCTAssertEqual(viewModel.unlockedCount, 0)
    }

    func testRefresh_MultipleCalls_AlwaysReturnsLatestData() {
        // Given
        mockAchievementService.totalPoints = 10
        viewModel.refresh()
        XCTAssertEqual(viewModel.totalPoints, 10)

        // When
        mockAchievementService.totalPoints = 50
        viewModel.refresh()

        // Then
        XCTAssertEqual(viewModel.totalPoints, 50)
    }

    func testRefresh_WithTodayPoints_ThenReflectsCorrectly() {
        // Given
        mockAchievementService.todaysPoints = 30

        // When
        viewModel.refresh()

        // Then
        XCTAssertEqual(viewModel.todayPoints, 30)
    }
}

import Foundation
import Combine

// MARK: - AchievementViewModel

final class AchievementViewModel: ObservableObject {
    // MARK: - Dependencies

    private let achievementService: AchievementServiceProtocol

    // MARK: - Published Properties

    /// 所有成就列表
    @Published var achievements: [Achievement] = []
    /// 已解锁的成就数量
    @Published var unlockedCount: Int = 0
    /// 累计获得的总积分
    @Published var totalPoints: Int = 0
    /// 今日获得的积分
    @Published var todayPoints: Int = 0

    // MARK: - Init

    init(achievementService: AchievementServiceProtocol) {
        self.achievementService = achievementService

        // 初始化时加载数据
        refresh()
    }

    // MARK: - Public Methods

    /// 刷新所有成就数据
    func refresh() {
        achievements = achievementService.fetchAllAchievements()
        unlockedCount = achievementService.getUnlockedAchievementCount()
        totalPoints = achievementService.getTotalPoints()
        todayPoints = achievementService.getTodaysPoints()
    }
}

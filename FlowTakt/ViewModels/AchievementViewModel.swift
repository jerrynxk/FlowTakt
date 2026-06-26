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

        // 监听数据库重置通知，及时清理已删除的 NSManagedObject 引用
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDatabaseReset),
            name: .databaseDidReset,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Private Methods

    @objc private func handleDatabaseReset() {
        // 立即清空已删除的对象引用，防止 SwiftUI ForEach 访问崩溃
        achievements = []
        unlockedCount = 0
        totalPoints = 0
        todayPoints = 0
        // 异步重新加载（等待新 store 完全就绪）
        DispatchQueue.main.async { [weak self] in
            self?.refresh()
        }
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

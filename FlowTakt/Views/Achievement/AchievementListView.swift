import SwiftUI

// MARK: - 成就主视图

struct AchievementListView: View {
    @EnvironmentObject var achievementViewModel: AchievementViewModel
    @EnvironmentObject var l10n: L10n
    @State private var justUnlockedAchievement: Achievement? = nil

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    /// 按分类排序的成就列表
    private var groupedAchievements: [(category: AchievementCategory, achievements: [Achievement])] {
        let dict = Dictionary(grouping: achievementViewModel.achievements) { achievement in
            AchievementCategory(rawValue: achievement.category) ?? .special
        }

        // 按固定顺序排列分类
        let order: [AchievementCategory] = [.total, .streak, .speed, .special]
        return order.compactMap { category in
            guard let items = dict[category], !items.isEmpty else { return nil }
            return (category, items)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 20) {
                    // 积分概览
                    PointsDisplayView()
                        .environmentObject(achievementViewModel)
                        .padding(.horizontal)

                    // 分类成就网格
                    ForEach(groupedAchievements, id: \.category) { group in
                        categorySection(group: group)
                    }

                    // 底部留白
                    Color.clear.frame(height: 20)
                }
                .padding(.top, 12)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle(L10n.shared.成就)
            .refreshable {
                achievementViewModel.refresh()
            }
            .unlockOverlay(
                achievement: justUnlockedAchievement,
                onDismiss: { justUnlockedAchievement = nil }
            )
        }
    }

    // MARK: - 分类区域

    private func categorySection(group: (category: AchievementCategory, achievements: [Achievement])) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // 分类标题
            sectionHeader(group: group)

            // 成就网格
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(group.achievements) { achievement in
                    AchievementBadgeView(achievement: achievement)
                        .environmentObject(achievementViewModel)
                        .onTapGesture {
                            handleTap(achievement: achievement)
                        }
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - 分类标题

    private func sectionHeader(group: (category: AchievementCategory, achievements: [Achievement])) -> some View {
        let unlockedCount = group.achievements.filter(\.isUnlocked).count
        let totalCount = group.achievements.count
        let color = AchievementBadgeColor.color(for: group.category)

        return HStack {
            // 分类名称
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)

                Text(group.category.displayName)
                    .font(.headline.weight(.semibold))
            }

            Spacer()

            // 进度
            Text("\(unlockedCount)/\(totalCount)")
                .font(.subheadline.monospacedDigit())
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color(.tertiarySystemFill))
                )
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    // MARK: - 交互

    private func handleTap(achievement: Achievement) {
        // 仅在已解锁时可触发庆祝动画
        guard achievement.isUnlocked else { return }
        justUnlockedAchievement = achievement
    }
}

// MARK: - AchievementCategory 显示名称

extension AchievementCategory {
    var displayName: String {
        L10n.shared.achievementCategory(self.rawValue)
    }
}

/// 成就分类颜色（与 AchievementBadgeView 保持一致）
private enum AchievementBadgeColor {
    static func color(for category: AchievementCategory) -> Color {
        switch category {
        case .streak:
            return .orange
        case .total:
            return Color.breakGreen
        case .speed:
            return Color.longBreakBlue
        case .special:
            return Color.focusRed
        }
    }
}

// MARK: - 预览

#if DEBUG
struct AchievementListView_Previews: PreviewProvider {
    static var previews: some View {
        AchievementListView()
            .environmentObject(AchievementViewModel(
                achievementService: AchievementService(
                    persistenceController: PersistenceController.shared,
                    focusService: FocusService(
                        persistenceController: PersistenceController.shared,
                        notificationService: NotificationService()
                    )
                )
            ))
    }
}
#endif

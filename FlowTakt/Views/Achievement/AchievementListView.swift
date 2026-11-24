import SwiftUI

// MARK: - 成就主视图

struct AchievementListView: View {
    @EnvironmentObject var achievementViewModel: AchievementViewModel
    @EnvironmentObject var l10n: L10n
    @State private var justUnlockedAchievement: Achievement? = nil

    // v1.3.4p：iPad 全量适配 — GridItem(.adaptive(minimum:160)) 让列数随容器宽度自动调整：
    // iPhone 紧凑宽度（~398pt）保持 2 列，iPad 13" regular 宽度（~1046pt）扩展到 5-6 列
    private let columns = [
        GridItem(.adaptive(minimum: 160, maximum: .infinity), spacing: 12)
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
            VStack(spacing: 0) {
                // 标题行：「成就」大标题（本页无操作按钮），紧贴顶部分段控件（2026-10-14）。
                // 消除系统 .large 大标题在分段控件下方留下的导航栏空档。
                titleRow

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
                .disableBounce()
            }
            .background(Color.appBackground)
            .navigationTitle(L10n.shared.成就)
            // 隐藏系统导航栏，标题行成为内容首项、紧贴顶部分段控件。
            // 保留 navigationTitle 供 VoiceOver / 深链标题使用。
            .toolbar(.hidden, for: .navigationBar)
            .unlockOverlay(
                achievement: justUnlockedAchievement,
                onDismiss: { justUnlockedAchievement = nil }
            )
        }
    }

    // MARK: - Title Row

    /// 标题行：「成就」大标题（本页无操作按钮）。
    /// 规格对齐 TaskListView.titleRow：largeTitle.bold、水平边距 16。
    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(L10n.shared.成就)
                .font(.largeTitle.weight(.bold))
                // 无障碍（2026-10-14）：大标题标记为一级标题（VoiceOver 转子可按标题跳转）
                .accessibilityHeading(.h1)
            Spacer(minLength: 12)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 4)
    }

    // MARK: - 分类区域

    private func categorySection(group: (category: AchievementCategory, achievements: [Achievement])) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // 分类标题
            sectionHeader(group: group)

            // 成就网格
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(group.achievements) { achievement in
                    Button {
                        handleTap(achievement: achievement)
                    } label: {
                        AchievementBadgeView(achievement: achievement)
                            .environmentObject(achievementViewModel)
                    }
                    .buttonStyle(.plain)
                    // 无障碍补齐（2026-11-02）：未解锁徽章的 handleTap 内部 guard 直接返回，
                    // 但读屏仍把它声明为可点按钮 → 「可点但毫无反馈」的假交互。
                    // 注意：不能用 .disabled()——实测它会对整个 label 子树再叠一层降透明度，
                    // 与 AchievementBadgeView 自身的 0.65 透明度叠加后文字几乎不可读（视觉回归）。
                    // 改为仅移除按钮语义：读屏播报为静态文本「初次专注，未解锁」，视觉零变化。
                    .accessibilityRemoveTraits(achievement.isUnlocked ? [] : .isButton)
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
                    // 无障碍（2026-10-14）：成就分类名标记为标题（VoiceOver 转子可按分类跳转）
                    .accessibilityHeading(.h2)
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
                    persistenceController: PersistenceController.shared
                ),
                persistenceController: PersistenceController.shared
            ))
            .environmentObject(L10n.shared)
    
}
}
#endif

import SwiftUI
import CoreData

// MARK: - 成就徽章组件

struct AchievementBadgeView: View {
    let achievement: Achievement

    @EnvironmentObject var achievementViewModel: AchievementViewModel

    private var isUnlocked: Bool { achievement.isUnlocked }
    private var categoryColor: Color { achievement.categoryColor }
    private var badgeSize: CGFloat { 80 }

    var body: some View {
        VStack(spacing: 8) {
            // 圆形徽章
            badgeCircle

            // 标题
            Text(achievement.title)
                .font(.caption.weight(.medium))
                .foregroundColor(isUnlocked ? .primary : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            // 描述
            Text(achievement.descriptionText ?? "")
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            // 进度条（未解锁时）
            if !isUnlocked {
                progressIndicator
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .opacity(isUnlocked ? 1.0 : 0.65)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - 圆形徽章

    private var badgeCircle: some View {
        ZStack {
            Circle()
                .fill(circleBackground)
                .frame(width: badgeSize, height: badgeSize)

            // 图标
            Image(systemName: achievement.systemImageName)
                .font(.system(size: 28))
                .foregroundStyle(isUnlocked ? .white : .secondary)
                .symbolRenderingMode(.hierarchical)

            // 锁定覆盖
            if !isUnlocked {
                lockOverlay
            }
        }
        .shadow(color: isUnlocked ? categoryColor.opacity(0.3) : .clear,
                radius: 6, x: 0, y: 3)
    }

    @ViewBuilder
    private var lockOverlay: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(.white)
            .padding(4)
            .background(Circle().fill(.ultraThinMaterial))
            .offset(x: badgeSize * 0.3, y: badgeSize * 0.3)
    }

    private var circleBackground: some ShapeStyle {
        if isUnlocked {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [categoryColor, categoryColor.opacity(0.7)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        } else {
            return AnyShapeStyle(Color(.quaternarySystemFill))
        }
    }

    // MARK: - 进度指示

    @ViewBuilder
    private var progressIndicator: some View {
        let progress = computeProgress()
        if let p = progress {
            ProgressView(value: p, total: 1.0)
                .tint(categoryColor.opacity(0.6))
                .frame(width: 60)
                .scaleEffect(x: 1, y: 0.6, anchor: .center)
        }
    }

    /// 根据成就类型计算进度（仅对可计算进度的成就类型有效）
    private func computeProgress() -> Double? {
        let threshold = Int(achievement.thresholdValue)
        guard threshold > 0 else { return nil }

        if achievement.identifier.hasPrefix("points_") {
            let current = min(achievementViewModel.totalPoints, threshold)
            return Double(current) / Double(threshold)
        }

        // 对于暂时无法获取中间值的成就类型，不显示进度条
        return nil
    }

    // MARK: - 辅助

    private var accessibilityLabel: String {
        if isUnlocked {
            return "\(achievement.title)，已解锁"
        } else {
            return "\(achievement.title)，未解锁"
        }
    }
}

// MARK: - Achievement 分类颜色与名称

extension Achievement {
    var categoryColor: Color {
        switch categoryEnum {
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

    var categoryDisplayName: String {
        switch categoryEnum {
        case .streak:
            return "连续成就"
        case .total:
            return "累积成就"
        case .speed:
            return "速度成就"
        case .special:
            return "特殊成就"
        }
    }

    private var categoryEnum: AchievementCategory {
        AchievementCategory(rawValue: category) ?? .special
    }
}

// MARK: - 预览

#if DEBUG
struct AchievementBadgeView_Previews: PreviewProvider {
    static var previews: some View {
        let unlocked = makeAchievement(isUnlocked: true)
        let locked = makeAchievement(isUnlocked: false)

        HStack(spacing: 16) {
            AchievementBadgeView(achievement: unlocked)
            AchievementBadgeView(achievement: locked)
        }
        .environmentObject(AchievementViewModel(
            achievementService: AchievementService(
                persistenceController: PersistenceController.shared,
                focusService: FocusService(
                    persistenceController: PersistenceController.shared,
                    notificationService: NotificationService()
                )
            )
        ))
        .padding()
        .background(Color.appBackground)
        .previewLayout(.sizeThatFits)
    }

    private static func makeAchievement(isUnlocked: Bool) -> Achievement {
        let ctx = PersistenceController.shared.viewContext
        let a = Achievement(context: ctx)
        a.id = UUID()
        a.identifier = "first_pomodoro"
        a.title = "初次专注"
        a.descriptionText = "完成你的第一个番茄钟"
        a.iconName = "star.fill"
        a.category = AchievementCategory.total.rawValue
        a.thresholdValue = 1
        a.isUnlocked = isUnlocked
        a.createdAt = Date()
        return a
    }
}
#endif

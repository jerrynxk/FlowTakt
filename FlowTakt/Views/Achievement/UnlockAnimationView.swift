import SwiftUI
import CoreData

// MARK: - 解锁庆祝动画

struct UnlockAnimationView: View {
    let achievement: Achievement
    let onDismiss: () -> Void

    @EnvironmentObject var l10n: L10n
    // 无障碍修复（2026-08-12）：尊重「减少动态效果」设置，动画降级为直接显示
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // 无障碍补齐（2026-11-02）：读屏开启时延长自动关闭时长，避免播报中途被抢走
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    @State private var showContent = false
    @State private var starBurst = false
    @State private var scaleUp = false

    private let animationDuration: Double = 0.6
    private let starCount = 12

    /// 修复（2026-10-14 P2）：本视图整体对 VoiceOver 隐藏（避免与卡片重复播报），
    /// 但解锁是必须被播报的事件 —— 原注释称「由触发方另行播报」，实测全仓无任何
    /// UIAccessibility.post 调用，等于读屏用户完全感知不到解锁。
    private func announceUnlocked() {
        UIAccessibility.post(notification: .announcement,
                             argument: achievement.title.isEmpty
                                ? L10n.shared.成就已解锁
                                : achievement.title)
    }

    var body: some View {
        ZStack {
            // 半透明背景（仅视觉遮罩：关闭动作由卡片承担，遮罩本身对读屏隐藏）
            Color.black.opacity(showContent ? 0.45 : 0)
                .ignoresSafeArea()
                .onTapGesture(perform: dismiss)
                .accessibilityHidden(true)

            // 星星爆发（纯装饰）
            ForEach(0..<starCount, id: \.self) { index in
                starParticle(index: index)
                    .accessibilityHidden(true)
            }

            // 主内容
            // 无障碍补齐（2026-11-02）：旧实现整视图 `.accessibilityHidden(true)`，
            // 而唯一的关闭路径是点击背景遮罩 → 读屏用户既听不到卡片内容、也无法主动关闭，
            // 只能等 2.5s 自动消失。现改为「遮罩/粒子隐藏 + 卡片合并为单个可点元素」：
            // 焦点可落在卡片上，双击即关闭，并在读屏开启时延长自动关闭时长。
            mainContent
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(unlockedAnnouncement)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(L10n.shared.双击关闭)
                .accessibilityAction { dismiss() }
                .onTapGesture(perform: dismiss)
        }
        .onAppear {
            startAnimation()
            // 修复（P2）：解锁事件必须被 VoiceOver 播报
            announceUnlocked()
        }
    }

    /// 卡片合并后的读屏文本：「成就解锁，标题，描述」
    private var unlockedAnnouncement: String {
        var parts = [L10n.shared.成就解锁]
        if !achievement.title.isEmpty { parts.append(achievement.title) }
        if let desc = achievement.descriptionText, !desc.isEmpty { parts.append(desc) }
        return parts.joined(separator: "，")
    }

    // MARK: - 主内容

    private var mainContent: some View {
        VStack(spacing: 16) {
            // 徽章图标
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [achievement.categoryColor, achievement.categoryColor.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                    .shadow(color: achievement.categoryColor.opacity(0.5), radius: 12, x: 0, y: 4)

                Image(systemName: achievement.systemImageName)
                    .font(.system(size: 40))
                    .foregroundColor(.white)
                    .symbolRenderingMode(.hierarchical)
            }
            .scaleEffect(scaleUp ? 1 : 0.3)
            .rotationEffect(.degrees(scaleUp ? 0 : -30))

            // 文字
            Text(L10n.shared.成就解锁)
                .font(.title2.weight(.bold))
                .foregroundColor(.white)

            Text(achievement.title)
                .font(.title.weight(.heavy))
                .foregroundColor(.white)

            Text(achievement.descriptionText ?? "")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(.vertical, 40)
        .padding(.horizontal, 24)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .opacity(scaleUp ? 1 : 0)
        .scaleEffect(scaleUp ? 1 : 0.5)
    }

    // MARK: - 星星粒子

    private func starParticle(index: Int) -> some View {
        let angle = 2 * .pi * Double(index) / Double(starCount)
        let distance: CGFloat = starBurst ? 140 : 20
        let rotation = Angle.degrees(Double(index) * (360 / Double(starCount)))

        return Image(systemName: "star.fill")
            .font(.system(size: 12))
            .foregroundColor(achievement.categoryColor.opacity(starBurst ? 0.8 : 0))
            .rotationEffect(rotation)
            .offset(
                x: cos(angle) * distance,
                y: sin(angle) * distance
            )
            .scaleEffect(starBurst ? 1 : 0.2)
    }

    // MARK: - 动画编排

    private func startAnimation() {
        // 减少动态效果：跳过动画直接显示最终状态（无缩放/星星爆发/淡入过渡）
        guard !reduceMotion else {
            showContent = true
            scaleUp = true
            return
        }
        withAnimation(.easeOut(duration: 0.25)) {
            showContent = true
        }

        withAnimation(.interpolatingSpring(
            stiffness: 120, damping: 10, initialVelocity: 0
        ).delay(0.15)) {
            scaleUp = true
        }

        withAnimation(.easeOut(duration: 0.5).delay(0.2)) {
            starBurst = true
        }

        // 自动消失（无障碍补齐 2026-11-02：读屏开启时延长到 8s，
        // 原 2.5s 会在播报「成就解锁 + 标题 + 描述」时被打断）
        let autoDismissDelay: TimeInterval = voiceOverEnabled ? 8.0 : 2.5
        DispatchQueue.main.asyncAfter(deadline: .now() + autoDismissDelay) {
            dismiss()
        }
    }

    private func dismiss() {
        withAnimation(.easeIn(duration: 0.2)) {
            showContent = false
            scaleUp = false
            starBurst = false
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            onDismiss()
        }
    }
}

// MARK: - 使用示例：作为 overlay 的修饰器

struct UnlockOverlayModifier: ViewModifier {
    let achievement: Achievement?
    let onDismiss: () -> Void

    func body(content: Content) -> some View {
        content
            .overlay {
                if let achievement {
                    UnlockAnimationView(
                        achievement: achievement,
                        onDismiss: onDismiss
                    )
                    .transition(.identity)
                    .zIndex(100)
                }
            }
    }
}

extension View {
    func unlockOverlay(achievement: Achievement?, onDismiss: @escaping () -> Void) -> some View {
        modifier(UnlockOverlayModifier(achievement: achievement, onDismiss: onDismiss))
    }
}

// MARK: - 预览

#if DEBUG
struct UnlockAnimationView_Previews: PreviewProvider {
    static var previews: some View {
        let ctx = PersistenceController.shared.viewContext
        let achievement = Achievement(context: ctx)
        achievement.storageId = UUID()
        achievement.identifier = "first_pomodoro"
        achievement.title = "初次专注"
        achievement.descriptionText = "完成你的第一个番茄钟"
        achievement.iconName = "star.fill"
        achievement.category = AchievementCategory.total.rawValue
        achievement.thresholdValue = 1
        achievement.isUnlocked = true
        achievement.createdAt = Date()

        return UnlockAnimationView(achievement: achievement, onDismiss: {})
            .background(Color.appBackground)
            .environmentObject(L10n.shared)
    
}
}
#endif

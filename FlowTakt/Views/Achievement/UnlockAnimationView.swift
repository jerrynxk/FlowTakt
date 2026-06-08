import SwiftUI
import CoreData

// MARK: - 解锁庆祝动画

struct UnlockAnimationView: View {
    let achievement: Achievement
    let onDismiss: () -> Void

    @State private var showContent = false
    @State private var starBurst = false
    @State private var scaleUp = false

    private let animationDuration: Double = 0.6
    private let starCount = 12

    var body: some View {
        ZStack {
            // 半透明背景
            Color.black.opacity(showContent ? 0.45 : 0)
                .ignoresSafeArea()
                .onTapGesture(perform: dismiss)

            // 星星爆发
            ForEach(0..<starCount, id: \.self) { index in
                starParticle(index: index)
            }

            // 主内容
            mainContent
        }
        .onAppear(perform: startAnimation)
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
            Text("🎉 成就解锁！")
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

        // 自动消失
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
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
        achievement.id = UUID()
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
    }
}
#endif

import SwiftUI

// MARK: - 圆形计时器（升级版：三层圆环 + 内嵌阶段徽章）

struct CircularTimerView: View {
    @EnvironmentObject var focusViewModel: FocusViewModel
    @EnvironmentObject var l10n: L10n

    let progress: Double

    private let lineWidth: CGFloat = 12

    var body: some View {
        ZStack {
            // 外圈品牌色淡底环（待机也呈现品牌色，不再灰扑扑）
            Circle()
                .stroke(
                    Color.forPhase(focusViewModel.activePhase).opacity(0.18),
                    lineWidth: lineWidth
                )

            // 内层柔和填充（随进度显现的品牌色高光）
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.forPhase(focusViewModel.activePhase).opacity(progress > 0 ? 0.22 : 0.10),
                            Color.forPhase(focusViewModel.activePhase).opacity(0.02)
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: 110
                    )
                )
                .padding(lineWidth + 6)

            // 待机空进度引导环（运行后由下方进度环覆盖）
            Circle()
                .trim(from: 0, to: progress == 0 ? 1 : 0)
                .stroke(
                    Color.forPhase(focusViewModel.activePhase).opacity(0.14),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            // 进度描边（品牌色渐变，圆头线帽，带光晕）
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        colors: [
                            Color.forPhase(focusViewModel.activePhase).opacity(0.55),
                            Color.forPhase(focusViewModel.activePhase)
                        ],
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: Color.forPhase(focusViewModel.activePhase).opacity(0.55), radius: 10, x: 0, y: 0)
                .animation(.linear(duration: 0.1), value: progress)

            // 中心内容：阶段徽章 + 时间（v1.3.4p 第三轮：状态文字移出 circularTimerView 到 FocusView body，
//                          避免主按钮覆盖——circularTimerView 在圆环 VStack 内，被 padding.top 20 包裹后，
//                          圆环底部空间紧，状态文字放底部会与主按钮再次重叠）
VStack(spacing: 6) {
    FocusPhaseBadge()

    Text(focusViewModel.timerDisplay)
        // v1.3.4p：字号 60pt（保留视觉主信息），圆环 ringSize 上限同步 280→240，
        // 文字距圆环底部 stroke + 外发光阴影有 90pt buffer，iPhone 上 ringSize 由 width*0.56 自然限定
        .font(.system(size: 60, weight: .bold, design: .monospaced))
        .foregroundColor(.primary)
        .multilineTextAlignment(.center)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        // 无障碍：限制动态字体放大上限，避免大字号模式溢出圆环（时间已由外层 accessibilityLabel 朗读）
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .contentTransition(.numericText())
        .animation(.linear(duration: 0.1), value: focusViewModel.timerDisplay)
        .accessibilityHidden(true)
}
.padding(.horizontal, 8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(timerAccessibilityText)
        .accessibilityValue(
            focusViewModel.timerState == .running ? L10n.shared.进行中
            : focusViewModel.timerState == .paused ? L10n.shared.已暂停
            : focusViewModel.timerState == .finished ? L10n.shared.已完成
            : L10n.shared.准备就绪
        )
    }

    /// VoiceOver 友好时间：避免读成 "25比0"，转为 "剩余 25 分 0 秒"
    private var timerAccessibilityText: String {
        let parts = focusViewModel.timerDisplay.split(separator: ":")
        if parts.count == 2, let minutes = Int(parts[0]), let seconds = Int(parts[1]) {
            return L10n.shared.计时剩余(minutes, seconds)
        }
        return focusViewModel.timerDisplay
    }
}

#if DEBUG
struct CircularTimerView_Previews: PreviewProvider {
    static var previews: some View {
        CircularTimerView(progress: 0.3)
            .environmentObject(FocusViewModel(
                focusService: FocusService(
                    persistenceController: PersistenceController.shared,
                    notificationService: NotificationService()
                ),
                timerManager: TimerManager(),
                notificationService: NotificationService(),
                appBlockerService: AppBlockerService(),
                audioService: AudioService(),
                achievementService: AchievementService(
                    persistenceController: PersistenceController.shared
                ),
                taskService: TaskService(persistenceController: PersistenceController.shared),
                speechService: SpeechService()
            ))
            .frame(width: 250, height: 250)
            .padding()
    }
}
#endif

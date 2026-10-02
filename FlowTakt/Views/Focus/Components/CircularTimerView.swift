import SwiftUI

// MARK: - 圆形计时器（v1.3.4 视觉重设计）
//
// 设计要点（2026-10-03 重做）：
// 1. **层级收敛**：旧实现有 4 层同色系圆环叠加（外圈淡底环 + 径向渐变填充 +
//    待机引导环 + 进度环），同色叠加在浅灰背景上会形成一圈"脏粉晕"，边界模糊。
//    现收敛为 2 层：中性轨道 + 进度弧。轨道改用 systemGray4 而非同色淡粉，
//    避免"底环 / 进度环"颜色相近导致的辨识度下降。
// 2. **中心有依托**：中心区加一层极淡的品牌色圆底（替代旧版的 RadialGradient），
//    既给数字一个视觉落点，又不会在圆心堆出颜色。徽章与时间间距重新分配
//    （旧版 spacing 6 使重心偏上、下方留白过大），改为自适应间距。
// 3. **进度弧端点**：圆头线帽 + 外侧柔光，运行中随进度推进有明确的"头部"指示。
// 4. **字体**：`design: .rounded` 的等宽数字，比 `design: .monospaced` 的
//    机械感更强，视觉重心更集中。

struct CircularTimerView: View {
    @EnvironmentObject var focusViewModel: FocusViewModel
    @EnvironmentObject var l10n: L10n

    let progress: Double

    /// 进度环线宽（较旧实现 12 → 10，配合两层结构更显精致）
    private let lineWidth: CGFloat = 10

    private var phaseColor: Color {
        Color.forPhase(focusViewModel.activePhase)
    }

    /// 是否处于计时中（决定轨道/中心的呈现强度）
    private var isActive: Bool {
        progress > 0
    }

    var body: some View {
        ZStack {
            // MARK: 第 1 层：中性轨道
            // 旧实现用 phaseColor.opacity(0.18) 作底环，与进度弧同色系；
            // 现改为中性灰，仅在运行中染上极淡品牌色，保持"未开始"的静默感。
            Circle()
                .stroke(
                    Color(.systemGray4).opacity(isActive ? 0.55 : 1.0),
                    lineWidth: lineWidth
                )

            // MARK: 第 2 层：进度弧
            // 圆头线帽 + 柔光，运行中头部位置即当前进度落点。
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        colors: [
                            phaseColor.opacity(0.65),
                            phaseColor
                        ],
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: phaseColor.opacity(0.45), radius: 8)
                .animation(.linear(duration: 0.1), value: progress)

            // MARK: 中心：极淡圆底 + 徽章 + 时间
            // 旧版用 RadialGradient(startRadius 10 / endRadius 110)，圆心颜色堆积明显；
            // 现改为单一低透明度填充，视觉更干净。
            // padding 再收 10pt：避免中心底色撑到进度弧内侧，把弧线的存在感压掉。
            Circle()
                .fill(phaseColor.opacity(isActive ? 0.07 : 0.04))
                .padding(lineWidth + 24)

            VStack(spacing: 10) {
                FocusPhaseBadge()

                Text(focusViewModel.timerDisplay)
                    // rounded 设计比 monospaced 更柔和，避免机械感；
                    // .monospacedDigit() 单独保留数字等宽特性，防止时间跳动时左右抖动。
                    .font(.system(size: 56, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .contentTransition(.numericText())
                    .animation(.linear(duration: 0.1), value: focusViewModel.timerDisplay)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 10)
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
        VStack(spacing: 24) {
            // 待机
            previewRing(label: "待机 · 0%")
                .environmentObject(makeVM())

            // 运行中
            previewRing(label: "专注中 · 62%")
                .environmentObject(makeVM())

            // 休息阶段
            previewRing(label: "短休息 · 30%")
                .environmentObject(makeVM())
        }
        .padding()
    }

    @ViewBuilder
    private static func previewRing(label: String) -> some View {
        VStack(spacing: 6) {
            Text(label).font(.caption).foregroundColor(.secondary)
            CircularTimerView(progress: label.contains("62") ? 0.62 : (label.contains("30") ? 0.3 : 0))
                .frame(width: 220, height: 220)
        }
    }

    private static func makeVM() -> FocusViewModel {
        FocusViewModel(
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
        )
    }
}
#endif

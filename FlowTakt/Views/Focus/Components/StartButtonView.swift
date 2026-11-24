import SwiftUI

// MARK: - 主控按钮（v1.3.2 精致化：缩小按钮 + 干净实色圆 + 微阴影）
// 设计要点：
// 1. 56pt 主按钮（开始/暂停切换）+ 48pt Stop 副按钮（仅运行时显示）
// 2. 主按钮用实色 phaseColor 填充 + 22pt SF Symbol + 微阴影，避开 .borderedProminent 在 iOS 16 上
//    偏"按钮感"的 elevation，纯靠色彩+留白表达视觉层级
// 3. 长按主按钮 0.6s 仍唤起"放弃原因"二次确认，作为防止误触的深度保护
// 4. Stop 按钮单击直接放弃（不走 reason 弹窗），符合"想停就停"的操作直觉
// 审查修复（2026-08-12）：移除从未正确显示的"长按 halo 进度"死逻辑（LongPressGesture.onChanged
//    只在 0.6s 成功瞬间触发一次，onEnded 随即取消，进度动画永不运行），保留长按唤起放弃功能。

struct StartButtonView: View {
    @EnvironmentObject var focusViewModel: FocusViewModel
    @EnvironmentObject var l10n: L10n

    private var phaseColor: Color {
        Color.forPhase(focusViewModel.activePhase)
    }

    private var isIdle: Bool { focusViewModel.timerState == .idle }
    private var isRunning: Bool { focusViewModel.timerState == .running }
    private var isPaused: Bool { focusViewModel.timerState == .paused }
    private var isActive: Bool { isRunning || isPaused }

    /// 长按是否触发（避免松手时短按继续触发）
    @State private var longPressTriggered = false
    /// 中断原因选择弹窗
    @State private var showReasonDialog = false
    /// 自定义原因输入
    @State private var customReason = ""
    @State private var showCustomReasonAlert = false

    private let mainButtonSize: CGFloat = 56
    private let stopButtonSize: CGFloat = 48
    private let longPressThreshold: TimeInterval = 0.6

    var body: some View {
        HStack(spacing: 16) {
            mainButton

            // Stop 副按钮：仅在运行中 / 暂停时显示
            // 单击 = 直接 abandon（无 reason 弹窗），符合"想停就停"的极简直觉
            if isActive {
                stopButton
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: focusViewModel.timerState)
        .confirmationDialog(
            L10n.shared.为什么中断了这个番茄,
            isPresented: $showReasonDialog,
            titleVisibility: .visible
        ) {
            Button(L10n.shared.原因电话) { abandon(with: L10n.shared.原因电话) }
            Button(L10n.shared.原因临时有事) { abandon(with: L10n.shared.原因临时有事) }
            Button(L10n.shared.原因身体不适) { abandon(with: L10n.shared.原因身体不适) }
            Button(L10n.shared.原因想休息) { abandon(with: L10n.shared.原因想休息) }
            Button(L10n.shared.原因其他) {
                customReason = ""
                showCustomReasonAlert = true
            }
            Button(L10n.shared.取消, role: .cancel) {}
        }
        .alert(L10n.shared.中断原因, isPresented: $showCustomReasonAlert) {
            TextField(L10n.shared.原因其他, text: $customReason)
            Button(L10n.shared.取消, role: .cancel) {}
            Button(L10n.shared.确定) {
                let trimmed = customReason.trimmingCharacters(in: .whitespacesAndNewlines)
                abandon(with: trimmed.isEmpty ? nil : trimmed)
            }
        } message: {
            Text(L10n.shared.为什么中断了这个番茄)
        }
    }

    // MARK: - Main button (开始 / 暂停)

    private var mainButton: some View {
        // 主按钮本体：实色圆 + 微阴影，避开 iOS 16 borderedProminent 的"按钮"硬感
        // 微阴影让按钮"漂浮"，但不出现 12+pt 的夸张 halo
        //
        // 精致化（2026-11-02）：
        // 1. 顶部到底部加同色渐变（上部略透），避免纯平涂的"色块"感；
        // 2. 外圈加一层模糊柔光，把按钮从纯黑背景中托起 —— 深色下单个红色圆盘
        //    直接落在 #000 上会显得"贴"在背景里，柔光给出轻微悬浮的空间感；
        // 3. 内圈 1pt 白色高光描边，模拟受光边缘，提升体积感；
        // 4. 按下时缩放至 0.94（PressableScaleStyle），提供明确的触觉呼应。
        Button(action: handleTap) {
            ZStack {
                // 外柔光（不参与布局：外层 frame 固定为按钮尺寸）
                Circle()
                    .fill(phaseColor.opacity(0.22))
                    .frame(width: mainButtonSize * 1.34, height: mainButtonSize * 1.34)
                    .blur(radius: 11)

                Image(systemName: mainIcon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: mainButtonSize, height: mainButtonSize)
                    .background(
                        Circle().fill(
                            LinearGradient(
                                colors: [
                                    phaseColor.opacity(0.92),
                                    phaseColor
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    )
                    .overlay(
                        Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                    )
                    .shadow(
                        color: phaseColor.opacity(0.30),
                        radius: 8,
                        x: 0,
                        y: 4
                    )
            }
            // 固定占位尺寸：柔光溢出绘制但不在 HStack 中占据额外空间，
            // 保证与 Stop 按钮的 16pt 间距不因光晕而偏移
            .frame(width: mainButtonSize, height: mainButtonSize)
        }
        .buttonStyle(PressableScaleStyle())
        .accessibilityLabel(mainLabel)
        .accessibilityHint(L10n.shared.长按时长手势提示)
        .contentShape(Circle())
        // 长按 0.6s 唤起放弃（深度保护）；单击切换状态
        .simultaneousGesture(
            LongPressGesture(minimumDuration: longPressThreshold)
                .onEnded { _ in
                    guard isActive else { return }
                    longPressTriggered = true
                    showReasonDialog = true
                }
        )
    }

    // MARK: - Stop button（显式停止）

    private var stopButton: some View {
        Button {
            abandon(with: nil)
        } label: {
            Image(systemName: "stop.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: stopButtonSize, height: stopButtonSize)
                .background(
                    Circle()
                        // 深色修复（2026-11-02）：systemGray6 在深色下接近纯黑，
                        // 与页面背景同色 → 圆盘消失；改用卡片同色阶并补极细描边
                        .fill(Color(.secondarySystemGroupedBackground))
                )
                .overlay(
                    Circle().strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5)
                )
        }
        .buttonStyle(PressableScaleStyle())
        .accessibilityLabel(L10n.shared.停止)
    }

    // MARK: - Actions

    private func handleTap() {
        // 长按已触发 reason 弹窗时，松手不再走 tap
        if longPressTriggered {
            longPressTriggered = false
            return
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            switch focusViewModel.timerState {
            case .idle, .finished:
                focusViewModel.startFocus(phase: focusViewModel.activePhase)
            case .running:
                focusViewModel.pauseFocus()
            case .paused:
                focusViewModel.resumeFocus()
            }
        }
    }

    /// 取消 + 记录中断原因（可空）
    private func abandon(with reason: String?) {
        focusViewModel.abandonSession(reason: reason)
    }

    // MARK: - Icons & labels

    private var mainLabel: String {
        switch focusViewModel.timerState {
        case .idle: return L10n.shared.开始
        case .running: return L10n.shared.暂停
        case .paused: return L10n.shared.恢复
        case .finished: return L10n.shared.开始
        }
    }

    private var mainIcon: String {
        switch focusViewModel.timerState {
        case .idle, .finished: return "play.fill"
        case .running: return "pause.fill"
        case .paused: return "play.fill"
        }
    }
}

// MARK: - 可按压缩放样式（2026-11-02）
// 主控按钮需要在按下瞬间有明确的形态反馈：纯色圆按钮若只有颜色变化，
// 在深色背景上几乎不可感知。统一用 0.94 缩放 + 弹簧回弹，
// 与页面其它动效（spring 0.35 / damping 0.7）保持同一手感族。

private struct PressableScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

#if DEBUG
struct StartButtonView_Previews: PreviewProvider {
    static var previews: some View {
        StartButtonView()
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
            .environmentObject(L10n.shared)
    }
}
#endif

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
        Button(action: handleTap) {
            Image(systemName: mainIcon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: mainButtonSize, height: mainButtonSize)
                .background(
                    Circle()
                        .fill(phaseColor)
                )
                .shadow(
                    color: phaseColor.opacity(0.25),
                    radius: 6,
                    x: 0,
                    y: 3
                )
        }
        .buttonStyle(.plain)
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
                        .fill(Color(.systemGray6))
                )
        }
        .buttonStyle(.plain)
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

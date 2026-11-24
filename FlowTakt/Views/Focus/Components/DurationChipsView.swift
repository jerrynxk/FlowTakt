import SwiftUI

// MARK: - 时长预设 Menu（v1.3.4m：替代 FocusPresetSheet 整页 sheet，下拉菜单直接选时长启动）
// 点击 chip 弹出 Menu，列出当前阶段所有预设时长 + 立即以新时长启动。
// 替代旧版"自定义 chip → 整页 sheet → 选项"的两次交互路径。

struct DurationChipsView: View {
    @EnvironmentObject var focusViewModel: FocusViewModel

    var body: some View {
        Menu {
            ForEach(durationOptions, id: \.self) { duration in
                Button {
                    applyAndStart(duration: duration)
                } label: {
                    if currentMatches(duration) {
                        Label(L10n.shared.分钟(Int(duration) / 60), systemImage: "checkmark")
                    } else {
                        Text(L10n.shared.分钟(Int(duration) / 60))
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "slider.horizontal.3")
                    .font(.caption2)
                Text(L10n.shared.时长预设自定义)
                    .font(.footnote.weight(.medium))
                    // 无障碍（2026-10-15 AX5 实测）：独占整行后仍显示「自定义…」——
                    // Menu 标签默认按文本理想宽度布局但受父容器约束。允许缩放到 0.5
                    // 后仍可读（AX5 下约 7pt），保证任何字体档位都不出现省略号。
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .allowsTightening(true)
            }
            .foregroundColor(.secondary)
            .frame(minHeight: 32)
            .padding(.horizontal, 14)
            // 深色修复（2026-11-02）：底色原为 systemBackground —— 深色下纯黑，
            // 与纯黑页面同色，胶囊只剩一圈描边、内部"掏空"。
            // 改用 secondarySystemGroupedBackground（深色 #1C1C1E / 浅色白），
            // 与 cardStyle 同色阶，胶囊成为一片可见的面而非一条线。
            .background(
                Capsule()
                    .fill(Color(.secondarySystemGroupedBackground))
                    .overlay(
                        Capsule()
                            .strokeBorder(Color(.separator).opacity(0.45), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.shared.时长预设自定义)
        .accessibilityHint(L10n.shared.选择后立即开始专注)
    }

    // MARK: - 当前阶段对应的预设时长列表

    private var durationOptions: [TimeInterval] {
        switch focusViewModel.activePhase {
        case .focus:      return AppConstants.focusDurationOptions
        case .shortBreak: return AppConstants.shortBreakOptions
        case .longBreak:  return AppConstants.longBreakOptions
        }
    }

    // MARK: - 选中态判断

    private func currentMatches(_ duration: TimeInterval) -> Bool {
        let stored: TimeInterval
        let baseline: TimeInterval
        switch focusViewModel.activePhase {
        case .focus:
            stored   = UserDefaults.standard.double(forKey: "focusDuration")
            baseline = AppConstants.defaultFocusDuration
        case .shortBreak:
            stored   = UserDefaults.standard.double(forKey: "shortBreakDuration")
            baseline = AppConstants.defaultShortBreakDuration
        case .longBreak:
            stored   = UserDefaults.standard.double(forKey: "longBreakDuration")
            baseline = AppConstants.defaultLongBreakDuration
        }
        let normalized = stored == 0 ? baseline : stored
        return Int(normalized) == Int(duration)
    }

    // MARK: - 写默认值 + 启动

    /// 复用 FocusPresetSheet.applyAndStart 逻辑（含运行中先 abandon 的修复）；
    /// 简化为直接调用 FocusViewModel.startFocus（v1.3.4m 不再依赖 sheet 关闭时机）
    private func applyAndStart(duration: TimeInterval) {
        // 触觉反馈：时长选择（轻量选择反馈）
        HapticManager.shared.selectionFeedback()

        // 修复（2026-10-14 审查 P1-10）：先快照当前阶段。
        // abandonSession() 会把 activePhase 重置为 .focus，若之后再读 activePhase，
        // 「休息阶段运行中选预设」会启动一个**专注**（而不是所选的休息），轮次也被重置。
        let phase = focusViewModel.activePhase

        switch phase {
        case .focus:      focusViewModel.applyFocusDuration(duration)
        case .shortBreak: focusViewModel.applyShortBreakDuration(duration)
        case .longBreak:  focusViewModel.applyLongBreakDuration(duration)
        }
        // 审查修复（2026-08-12）：运行中/暂停态先放弃当前会话，再以新时长启动
        // 修复（2026-10-14 P2）：abandonSession 会把轮次重置为 1 —— 「改个时长」不该
        // 抹掉「每 N 轮长休息」的进度，故保留并在启动后恢复。
        let preservedRound = focusViewModel.currentRoundIndex
        if focusViewModel.timerState != .idle {
            focusViewModel.abandonSession()
        }
        focusViewModel.startFocus(phase: phase, durationOverride: duration)
        focusViewModel.restoreRoundIndex(preservedRound)
    }
}
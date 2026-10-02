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
            }
            .foregroundColor(.secondary)
            .frame(minHeight: 32)
            .padding(.horizontal, 14)
            .background(
                Capsule()
                    .stroke(Color(.systemGray3), lineWidth: 1)
                    .background(Capsule().fill(Color(.systemBackground)))
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

        switch focusViewModel.activePhase {
        case .focus:      focusViewModel.applyFocusDuration(duration)
        case .shortBreak: focusViewModel.applyShortBreakDuration(duration)
        case .longBreak:  focusViewModel.applyLongBreakDuration(duration)
        }
        // 审查修复（2026-08-12）：运行中/暂停态先放弃当前会话，再以新时长启动
        if focusViewModel.timerState != .idle {
            focusViewModel.abandonSession()
        }
        focusViewModel.startFocus(phase: focusViewModel.activePhase, durationOverride: duration)
    }
}
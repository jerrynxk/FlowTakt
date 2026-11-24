import SwiftUI

// MARK: - 阶段切换 Segmented（v1.3.4c 移除二次确认）
// 与计划/习惯/统计页顶层完全一致：系统 .segmented Picker + 水平 16 / 垂直 8 边距。
// 由 FocusView 放在 NavigationStack **之外**（VStack 第一项），紧贴状态栏，
// 与大标题、阶段说明、内容形成与其它 Tab 一致的「Picker → 大标题 → 内容」视觉层级。
//
// v1.3.4c 调整：移除运行中的二次确认对话框。
// 理由：(1) 与其它 Tab 不一致（计划/习惯/统计 segmented 切换均为即时生效）；
//       (2) segmented 在 iOS 的交互语义即「快速切换」，二次确认打断操作流；
//       (3) 误触成本低（再点回原阶段即可恢复）；
//       (4) FocusViewModel.switchPhase 自身已处理「运行中先 abandon 再切」的语义。
// 现在任意状态下点击即切换，与系统 segmented 交互一致。

struct PhasePickerView: View {
    @EnvironmentObject var l10n: L10n

    /// 选中态由 FocusView 上提并统一驱动（点击 Segmented / 左右滑动均经此 Binding）
    @Binding var selection: FocusPhase

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(FocusPhase.allCases, id: \.self) { phase in
                Text(phaseShortName(phase)).tag(phase)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        // 无障碍（2026-10-14）：分段控件补用途标签（段位文本自解释，标签说明「这是什么选择」）
        .accessibilityLabel(L10n.shared.阶段)
        .accessibilityIdentifier("topTabPicker")
    }

    private func phaseShortName(_ phase: FocusPhase) -> String {
        switch phase {
        case .focus: return L10n.shared.focus
        case .shortBreak: return L10n.shared.短休息
        case .longBreak: return L10n.shared.长休息
        }
    }
}

// MARK: - 阶段说明行（2026-11-22 弱化：保留文案，降低视觉权重）
// 原规格 subheadline semibold primary + footnote secondary 与大标题争夺注意力，
// 「专注 / 深度聚焦」语义亦与分段控件、圆环徽章重复。
// 现降为 footnote secondary + caption2 tertiary，作为引导语退居次要层级。

struct PhaseCaptionView: View {
    @EnvironmentObject var focusViewModel: FocusViewModel
    @EnvironmentObject var l10n: L10n

    var body: some View {
        HStack(spacing: 5) {
            Text(titleForCurrentPhase)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("·")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
            Text(subtitleForCurrentPhase)
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .multilineTextAlignment(.center)
        // 无障碍补齐（2026-11-02）：三段文本 + 中点分隔符在此前会被 VoiceOver 拆成
        // 三个元素逐个朗读，「·」还会被读成「中点符号」。合并为一句：
        // 「深度聚焦，25 分钟专注」。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(titleForCurrentPhase + "，" + subtitleForCurrentPhase)
    }

    private var titleForCurrentPhase: String {
        switch focusViewModel.activePhase {
        case .focus: return L10n.shared.深度聚焦
        case .shortBreak: return L10n.shared.快速恢复
        case .longBreak: return L10n.shared.彻底放空
        }
    }

    private var subtitleForCurrentPhase: String {
        switch focusViewModel.activePhase {
        case .focus: return L10n.shared.深度聚焦副标题
        case .shortBreak: return L10n.shared.快速恢复副标题
        case .longBreak: return L10n.shared.彻底放空副标题
        }
    }
}
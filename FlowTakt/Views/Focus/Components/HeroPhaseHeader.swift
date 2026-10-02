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
    @EnvironmentObject var focusViewModel: FocusViewModel
    @EnvironmentObject var l10n: L10n

    /// 与 activePhase 镜像的本地选择（驱动系统 Segmented 选中态）
    @State private var selectedPhase: FocusPhase = .focus

    var body: some View {
        Picker("", selection: $selectedPhase) {
            ForEach(FocusPhase.allCases, id: \.self) { phase in
                Text(phaseShortName(phase)).tag(phase)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .onChange(of: selectedPhase) { newPhase in
            handleSelection(newPhase)
        }
        .onAppear {
            selectedPhase = focusViewModel.activePhase
        }
        .onChange(of: focusViewModel.activePhase) { newPhase in
            selectedPhase = newPhase
        }
    }

    // MARK: - 选中处理

    /// 处理 segmented 选择：直接调用 switchPhase（运行中由 ViewModel 自行处理 abandon）
    private func handleSelection(_ phase: FocusPhase) {
        guard phase != focusViewModel.activePhase else { return }
        focusViewModel.switchPhase(phase)
    }

    private func phaseShortName(_ phase: FocusPhase) -> String {
        switch phase {
        case .focus: return L10n.shared.focus
        case .shortBreak: return L10n.shared.短休息
        case .longBreak: return L10n.shared.长休息
        }
    }
}

// MARK: - 阶段说明行（v1.3.4 跟随大标题位置 · 规格与 DateSectionHeader 一致）
// 紧跟在 NavigationStack 大标题下方，与其它 section header 规格一致：
// subheadline semibold primary（标题）+ footnote secondary（副标题）。

struct PhaseCaptionView: View {
    @EnvironmentObject var focusViewModel: FocusViewModel
    @EnvironmentObject var l10n: L10n

    var body: some View {
        HStack(spacing: 6) {
            Text(titleForCurrentPhase)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.primary)
            Text("·")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text(subtitleForCurrentPhase)
                .font(.footnote)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .multilineTextAlignment(.center)
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
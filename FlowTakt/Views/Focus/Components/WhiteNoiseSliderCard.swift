import SwiftUI

// MARK: - 白噪音卡片（v1.3.3 紧凑版：单行 header + 单行 picker，节省垂直空间）
// 审查修复（2026-08-12）：移除未启用的音量死代码（volume @AppStorage + applyVolumeIfNeeded 空实现），
// 头注释同步澄清：紧凑版仅保留 Toggle + 类型 picker，音量细控待后续入口接入。

struct WhiteNoiseSliderCard: View {
    @EnvironmentObject var focusViewModel: FocusViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerRow
            typePicker
        }
        .padding(10)
        .cardStyle()
    }

    // MARK: - Header（紧凑版：icon + 标题 + 类型 segmented 同行）

    private var headerRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "speaker.waves.fill")
                .font(.system(size: 13))
                .foregroundColor(focusViewModel.isWhiteNoiseOn ? .focusRed : .secondary)
                // 无障碍修复（2026-08-12）：装饰图标不单独朗读
                .accessibilityHidden(true)

            Text(L10n.shared.白噪音)
                .font(.footnote.weight(.semibold))
                .foregroundColor(.primary)

            Spacer(minLength: 4)

            Toggle("", isOn: Binding(
                get: { focusViewModel.isWhiteNoiseOn },
                set: { _ in
                    // 触觉反馈：白噪音开关
                    HapticManager.shared.selectionFeedback()
                    focusViewModel.toggleWhiteNoise()
                }
            ))
            .labelsHidden()
            .tint(.focusRed)
            .scaleEffect(0.75)
            .accessibilityLabel(focusViewModel.isWhiteNoiseOn ? L10n.shared.白噪音开 : L10n.shared.白噪音关)
            .accessibilityIdentifier("whiteNoiseToggle")
        }
    }

    // MARK: - Type picker

    private var typePicker: some View {
        Picker("", selection: Binding(
            get: { focusViewModel.selectedWhiteNoiseType },
            set: { focusViewModel.setWhiteNoiseType($0) }
        )) {
            ForEach(WhiteNoiseType.allCases, id: \.self) { type in
                Text(type.localizedName).tag(type)
            }
        }
        .pickerStyle(.segmented)
        .disabled(!focusViewModel.isWhiteNoiseOn)
        .opacity(focusViewModel.isWhiteNoiseOn ? 1.0 : 0.55)
        .accessibilityLabel(L10n.shared.白噪音类型)
    }
}

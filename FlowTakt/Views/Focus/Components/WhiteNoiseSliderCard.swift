import SwiftUI

// MARK: - 白噪音卡片（v1.3.3：header + 当前音效选择行，点击从底部抽屉选音效）
// 审查修复（2026-08-12）：移除未启用的音量死代码（volume @AppStorage + applyVolumeIfNeeded 空实现），
// 头注释同步澄清：紧凑版仅保留 Toggle + 类型选择，音量细控待后续入口接入。

struct WhiteNoiseSliderCard: View {
    @EnvironmentObject var focusViewModel: FocusViewModel
    @State private var showSoundPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerRow
            selectionRow
        }
        .padding(10)
        .cardStyle()
        .sheet(isPresented: $showSoundPicker) {
            SoundPickerSheet(
                selected: focusViewModel.selectedWhiteNoiseType,
                onSelect: { type in
                    HapticManager.shared.selectionFeedback()
                    focusViewModel.setWhiteNoiseType(type)
                    showSoundPicker = false
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Header（icon + 标题 + Toggle 同行）

    private var headerRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "speaker.waves.fill")
                .font(.system(size: 13))
                .foregroundColor(focusViewModel.isWhiteNoiseEnabled ? .focusRed : .secondary)
                // 无障碍修复（2026-08-12）：装饰图标不单独朗读
                .accessibilityHidden(true)

            Text(L10n.shared.白噪音)
                .font(.footnote.weight(.semibold))
                .foregroundColor(.primary)

            Spacer(minLength: 4)

            Toggle("", isOn: Binding(
                get: { focusViewModel.isWhiteNoiseEnabled },
                set: { _ in
                    // 触觉反馈：白噪音开关（2026-11-22 起为纯偏好开关，不即时播放音频）
                    HapticManager.shared.selectionFeedback()
                    focusViewModel.toggleWhiteNoise()
                }
            ))
            .labelsHidden()
            .tint(.focusRed)
            .scaleEffect(0.75)
            .accessibilityLabel(focusViewModel.isWhiteNoiseEnabled ? L10n.shared.白噪音开 : L10n.shared.白噪音关)
            .accessibilityIdentifier("whiteNoiseToggle")
        }
    }

    // MARK: - 当前音效选择行（点击打开底部抽屉）

    private var selectionRow: some View {
        Button(action: {
            HapticManager.shared.selectionFeedback()
            showSoundPicker = true
        }) {
            HStack(spacing: 8) {
                Image(systemName: focusViewModel.selectedWhiteNoiseType.systemImage)
                    .font(.system(size: 13))
                    .foregroundColor(.focusRed)
                    .accessibilityHidden(true)

                Text(focusViewModel.selectedWhiteNoiseType.localizedName)
                    .font(.footnote.weight(.medium))
                    .foregroundColor(.primary)

                Spacer(minLength: 4)

                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            // 深色修复（2026-11-02）：secondarySystemFill 叠到 #1C1C1E 卡片上后
            // 与卡片底色几乎相同，选择行失去"可点"的暗示。改用 cardInsetFill
            // （深色提亮 / 浅色压暗的相对色），两种模式都能稳定读出一层层次。
            .background(Color.cardInsetFill)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color(.separator).opacity(0.35), lineWidth: 0.5)
            )
        }
        .disabled(!focusViewModel.isWhiteNoiseEnabled)
        .opacity(focusViewModel.isWhiteNoiseEnabled ? 1.0 : 0.55)
        .accessibilityLabel(L10n.shared.白噪音类型 + "：" + focusViewModel.selectedWhiteNoiseType.localizedName)
        .accessibilityHint(L10n.shared.选择环境音提示)
    }
}

// MARK: - 底部抽屉：环境音选择

struct SoundPickerSheet: View {
    let selected: WhiteNoiseType
    let onSelect: (WhiteNoiseType) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(WhiteNoiseType.allCases, id: \.self) { type in
                        SoundPickerRow(
                            type: type,
                            isSelected: selected == type
                        ) {
                            onSelect(type)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .navigationTitle(L10n.shared.环境音库)
            .navigationBarTitleDisplayMode(.inline)
            .disableBounce()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.shared.完成) { dismiss() }
                }
            }
        }
    }
}

struct SoundPickerRow: View {
    let type: WhiteNoiseType
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: type.systemImage)
                    .font(.system(size: 17))
                    .frame(width: 26, alignment: .center)
                    .foregroundColor(isSelected ? .focusRed : .primary)
                    .accessibilityHidden(true)

                Text(type.localizedName)
                    .font(.body)
                    .foregroundColor(.primary)

                Spacer(minLength: 4)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.focusRed)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(isSelected ? Color.focusRed.opacity(0.12) : Color(.secondarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .accessibilityLabel(type.localizedName)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityHint(isSelected ? L10n.shared.当前已选环境音 : L10n.shared.选择此环境音)
    }
}

// MARK: - 白噪音类型图标（SF Symbol 映射，供抽屉与选择行复用）

extension WhiteNoiseType {
    var systemImage: String {
        switch self {
        case .white:  return "waveform"
        case .rain:   return "cloud.rain"
        case .stream: return "water.waves"
        case .cafe:   return "cup.and.saucer"
        case .ocean:  return "wave.3.right"
        case .forest: return "tree"
        case .night:  return "moon.stars"
        case .wind:   return "wind"
        }
    }
}

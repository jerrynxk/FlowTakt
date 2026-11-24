import SwiftUI

// MARK: - CreateHabitSheetView

/// 新建习惯的 Sheet 视图（从 HabitListView 拆分出来以控制文件行数）
struct CreateHabitSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var l10n: L10n

    let onSave: (_ name: String, _ iconName: String?, _ colorHex: String?, _ frequency: String, _ targetCount: Int16) -> Void

    @State private var name: String = ""
    @State private var selectedIcon: String = "star"
    @State private var selectedColor: ColorOption = .red
    @State private var selectedFrequency: FrequencyOption = .daily
    @State private var targetCount: Int = 1

    private let icons: [String] = [
        "star", "heart", "book", "figure.run",
        "moon", "drop", "flame", "leaf",
        "brain", "dumbbell", "cup.and.saucer", "music.note"
    ]

    private let colorOptions: [ColorOption] = ColorOption.allCases

    enum FrequencyOption: CaseIterable {
        case daily
        case weekly
        case monthly

        var displayName: String {
            switch self {
            case .daily:   return L10n.shared.每天
            case .weekly:  return L10n.shared.每周
            case .monthly: return L10n.shared.每月
            }
        }

        var apiValue: String {
            switch self {
            case .daily:   return "daily"
            case .weekly:  return "weekly"
            case .monthly: return "monthly"
            }
        }
    }

    enum ColorOption: String, CaseIterable {
        case red, blue, green, orange, purple, pink, teal

        var color: Color {
            switch self {
            case .red:    return .red
            case .blue:   return .blue
            case .green:  return .green
            case .orange: return .orange
            case .purple: return .purple
            case .pink:   return .pink
            case .teal:   return .teal
            }
        }

        var hex: String {
            switch self {
            case .red:    return "FF3B30"
            case .blue:   return "007AFF"
            case .green:  return "34C759"
            case .orange: return "FF9500"
            case .purple: return "AF52DE"
            case .pink:   return "FF2D55"
            case .teal:   return "5AC8FA"
            }
        }

        /// 无障碍（2026-10-14）：读屏名本地化（此前直接播报 rawValue 英文 "red"/"teal"）
        var displayName: String {
            switch self {
            case .red:    return L10n.shared.红色
            case .blue:   return L10n.shared.蓝色
            case .green:  return L10n.shared.绿色
            case .orange: return L10n.shared.橙色
            case .purple: return L10n.shared.紫色
            case .pink:   return L10n.shared.粉色
            case .teal:   return L10n.shared.青色
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                // 名称
                Section(L10n.shared.名称) {
                    TextField(L10n.shared.习惯名称, text: $name)
                        .accessibilityLabel(L10n.shared.习惯名称)
                }

                // 图标选择
                Section(L10n.shared.图标) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 6), spacing: 12) {
                        ForEach(icons, id: \.self) { icon in
                            Button {
                                selectedIcon = icon
                            } label: {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(selectedIcon == icon ? selectedColor.color.opacity(0.2) : Color(.systemGray6))
                                        .frame(height: 44)

                                    Image(systemName: icon)
                                        .font(.system(size: 18, weight: .medium))
                                        .foregroundColor(selectedIcon == icon ? selectedColor.color : .secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(icon)
                            .accessibilityAddTraits(selectedIcon == icon ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                }

                // 颜色选择
                Section(L10n.shared.颜色) {
                    HStack(spacing: 12) {
                        ForEach(colorOptions, id: \.self) { option in
                            Button {
                                selectedColor = option
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(option.color)
                                        .frame(width: 32, height: 32)

                                    if selectedColor == option {
                                        Image(systemName: "checkmark")
                                            .font(.caption.weight(.bold))
                                            .foregroundColor(.white)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(option.displayName)
                            .accessibilityAddTraits(selectedColor == option ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                }

                // 频率选择
                Section(L10n.shared.频率) {
                    Picker(L10n.shared.频率, selection: $selectedFrequency) {
                        ForEach(FrequencyOption.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // 目标次数
                Section(L10n.shared.每日目标次数) {
                    Stepper(value: $targetCount, in: 1...99) {
                        Text(L10n.shared.targetCount(targetCount))
                            .fontWeight(.medium)
                    }
                }
            }
            .navigationTitle(L10n.shared.新建习惯)
            .navigationBarTitleDisplayMode(.inline)
            // 滚动统一调整（2026-11-02）：禁用弹性 + 柔化撞停减速
            .disableBounce()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.shared.取消) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.shared.保存) {
                        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        onSave(
                            name.trimmingCharacters(in: .whitespaces),
                            selectedIcon,
                            selectedColor.hex,
                            selectedFrequency.apiValue,
                            Int16(targetCount)
                        )
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

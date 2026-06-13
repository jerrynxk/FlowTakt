import SwiftUI

// MARK: - HabitListView

struct HabitListView: View {
    @EnvironmentObject var habitViewModel: HabitViewModel

    @State private var showCreateSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if habitViewModel.habits.isEmpty {
                    emptyState
                } else {
                    habitList
                }
            }
            .background(Color.appBackground)
            .navigationTitle(L10n.shared.习惯)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showCreateSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .fontWeight(.semibold)
                    }
                }
            }
            .sheet(isPresented: $showCreateSheet) {
                CreateHabitSheetView { name, iconName, colorHex, frequency, targetCount in
                    habitViewModel.createHabit(
                        name: name,
                        iconName: iconName,
                        colorHex: colorHex,
                        frequency: frequency,
                        targetCount: targetCount
                    )
                }
            }
        }
    }

    // MARK: - Habit List

    private var habitList: some View {
        List {
            ForEach(habitViewModel.habits) { habit in
                HabitRowView(habit: habit)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            withAnimation {
                                habitViewModel.deleteHabit(habit)
                            }
                        } label: {
                            Label(L10n.shared.删除, systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "star.circle")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))

            Text(L10n.shared.还没有习惯)
                .font(.title3)
                .fontWeight(.medium)
                .foregroundColor(.secondary)

            Text(L10n.shared.建立一个小习惯)
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                showCreateSheet = true
            } label: {
                Label(L10n.shared.创建第一个习惯, systemImage: "plus.circle.fill")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .tint(.focusRed)
            .padding(.top, 4)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - HabitRowView

private struct HabitRowView: View {
    @EnvironmentObject var habitViewModel: HabitViewModel
    @EnvironmentObject var l10n: L10n

    let habit: Habit

    var body: some View {
        HStack(spacing: 12) {
            // 图标
            habitIcon

            // 信息区
            VStack(alignment: .leading, spacing: 4) {
                // 名称 + 连续天数
                HStack(spacing: 6) {
                    Text(habit.name)
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Spacer()

                    streakBadge
                }

                // 频率 + 今日进度
                HStack(spacing: 8) {
                    frequencyLabel
                    progressLabel
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer()

            // 打卡按钮
            checkInButton
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    // MARK: - Habit Icon

    private var habitIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(habitColor.opacity(0.15))
                .frame(width: 40, height: 40)

            Image(systemName: habit.iconName ?? "star")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(habitColor)
        }
    }

    // MARK: - Streak Badge

    private var streakBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "flame.fill")
                .font(.caption2)
                .foregroundColor(.orange)

            Text("\(habit.currentStreak)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.orange)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(6)
    }

    // MARK: - Frequency Label

    private var frequencyLabel: some View {
        Text(frequencyText)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color(.systemGray6))
            .cornerRadius(4)
    }

    // MARK: - Progress Label

    private var progressLabel: some View {
        Text(L10n.shared.habitToday(todayCount, target: habit.targetCount))
    }

    // MARK: - Check-in Button

    private var checkInButton: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                if habitViewModel.dayHasRecord(habit: habit, date: Date()) {
                    // 移除打卡
                    if let todayRecord = todayRecord {
                        habitViewModel.removeCheckIn(record: todayRecord)
                    }
                } else {
                    // 打卡
                    habitViewModel.checkIn(habit: habit)
                }
            }
        } label: {
            if habitViewModel.dayHasRecord(habit: habit, date: Date()) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.green)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Image(systemName: "circle")
                    .font(.title2)
                    .foregroundColor(habitColor.opacity(0.5))
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private var habitColor: Color {
        guard let hex = habit.colorHex else { return .focusRed }
        return Color(hex: hex)
    }

    private var frequencyText: String {
        switch habit.frequency {
        case "daily":   return L10n.shared.每天
        case "weekly":  return L10n.shared.每周
        case "monthly": return L10n.shared.每月
        default:        return habit.frequency
        }
    }

    private var todayRecords: [HabitRecord] {
        habitViewModel.records(for: habit, in: 1).filter { $0.date.isToday }
    }

    private var todayCount: Int {
        todayRecords.count
    }

    /// 获取今天的打卡记录（用于取消打卡）
    private var todayRecord: HabitRecord? {
        todayRecords.first
    }
}

// MARK: - CreateHabitSheetView

private struct CreateHabitSheetView: View {
    @Environment(\.dismiss) private var dismiss

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
    }

    var body: some View {
        NavigationStack {
            Form {
                // 名称
                Section(L10n.shared.名称) {
                    TextField(L10n.shared.习惯名称, text: $name)
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

// MARK: - Preview

#Preview {
    HabitListView()
        .environmentObject(AppDependency().habitViewModel)
}

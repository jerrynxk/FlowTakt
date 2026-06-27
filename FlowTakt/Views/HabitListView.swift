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
        // 预计算每个习惯的今日记录，避免每行重复查询 CoreData（P1-14 性能优化）
        let todayRecordsByHabit: [UUID: [HabitRecord]] = {
            var dict: [UUID: [HabitRecord]] = [:]
            for habit in habitViewModel.habits {
                let records = habitViewModel.records(for: habit, in: 1).filter { $0.date.isToday }
                dict[habit.id] = records
            }
            return dict
        }()

        return List {
            ForEach(habitViewModel.habits) { habit in
                HabitRowView(
                    habit: habit,
                    todayRecords: todayRecordsByHabit[habit.id] ?? []
                )
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

            Text(L10n.shared.noHabits)
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
    /// 预计算的今日记录（避免每次 body 重绘都重新查询 CoreData）
    let todayRecords: [HabitRecord]

    var body: some View {
        HStack(spacing: 12) {
            // 图标
            habitIcon
                .accessibilityHidden(true)

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
        .accessibilityElement(children: .contain)
        .accessibilityLabel(habit.name)
        .accessibilityValue(L10n.shared.habitToday(todayCount, target: habit.targetCount))
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
        .accessibilityLabel(L10n.shared.连续专注)
        .accessibilityValue("\(habit.currentStreak) \(L10n.shared.天)")
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
                    if let todayRecord = todayRecords.first {
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
        .accessibilityLabel(habitViewModel.dayHasRecord(habit: habit, date: Date()) ? L10n.shared.完成 : L10n.shared.计时)
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

    private var todayCount: Int {
        todayRecords.count
    }
}

// MARK: - Preview

#Preview {
    HabitListView()
        .environmentObject(AppDependency().habitViewModel)
}

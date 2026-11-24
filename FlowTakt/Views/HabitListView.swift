import SwiftUI

// MARK: - HabitListView

struct HabitListView: View {
    @EnvironmentObject var habitViewModel: HabitViewModel

    @State private var showCreateSheet = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 标题行：「习惯」大标题 + 「+」新建按钮（同一行），紧贴顶部分段控件（2026-10-14）。
                // 原先「+」挂在导航栏 primaryAction、大标题由 .large 模式渲染，
                // 系统把按钮渲染在标题上方并额外预留导航栏高度，视觉上下分离；
                // 现改为内容区自绘标题行，与「任务」页（TaskListView）保持同构。
                titleRow

                Group {
                    if habitViewModel.habits.isEmpty {
                        emptyState
                    } else {
                        habitList
                    }
                }
            }
            .background(Color.appBackground)
            .navigationTitle(L10n.shared.习惯)
            // 隐藏系统导航栏，标题行成为内容首项、紧贴顶部分段控件。
            // 保留 navigationTitle 供 VoiceOver / 深链标题使用。
            .toolbar(.hidden, for: .navigationBar)
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

    // MARK: - Title Row

    /// 标题行：「习惯」大标题 + 「+」新建按钮（同一行）。
    /// 规格对齐 TaskListView.titleRow：largeTitle.bold、水平边距 16、按钮 44×44 命中区、focusRed 着色。
    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(L10n.shared.习惯)
                .font(.largeTitle.weight(.bold))
                // 无障碍（2026-10-14）：大标题标记为一级标题（VoiceOver 转子可按标题跳转）
                .accessibilityHeading(.h1)
            Spacer(minLength: 12)
            Button {
                showCreateSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.focusRed)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.shared.新建习惯)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 4)
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
                    // 修复（2026-10-14 P2）：删除习惯会级联清空全部打卡记录，全滑删除风险太高 →
        // 改为必须滑动到位并点「删除」按钮才生效
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
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
        // 滚动统一调整（2026-11-02）：禁用弹性 + 柔化撞停减速
        .disableBounce()
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "star.circle")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))
                // 无障碍（2026-10-14）：空状态装饰图标不单独朗读
                .accessibilityHidden(true)

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
            .accessibilityLabel(L10n.shared.创建第一个习惯)

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
        // 无障碍修复（2026-08-12）：未打卡读「打卡」而非语义错误的「计时」
        .accessibilityLabel(habitViewModel.dayHasRecord(habit: habit, date: Date()) ? L10n.shared.完成 : L10n.shared.打卡)
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
        .environmentObject(L10n.shared)
}

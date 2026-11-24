import SwiftUI
import CoreData

// MARK: - 专注页辅助工具条（2026-11-22 页面简化）
// 原「时长胶囊 / 关联任务卡 / 白噪音卡 / 今日统计卡」四块垂直堆叠 →
// 收成一行系统原生按钮，功能 100% 保留：
//   · 时长 → Menu（复用时长预设选择 + 立即启动逻辑）
//   · 任务 → Menu（复用任务绑定选择）
//   · 白噪音 → Menu（顶部对勾开关 + 下方各音效，一层直达；2026-11-22 简化）
//   · 统计 → sheet 内嵌 TodayOverviewSheetView（今日概览仪表盘，2026-11-22 重设计）
// 全部按钮带状态可视化（任务已绑定 / 白噪音已开 → 图标高亮）。

struct FocusToolbarView: View {
    @EnvironmentObject var focusViewModel: FocusViewModel
    @EnvironmentObject var taskViewModel: TaskViewModel
    @EnvironmentObject var statsViewModel: StatsViewModel
    @EnvironmentObject var l10n: L10n

    @State private var showStats = false
    // 白噪音自绘弹层（2026-11-22）：系统 Menu 会强制覆盖子视图颜色（foregroundColor 无效），
    // 无法实现「选中红色高亮 / 未选中灰字」，故改为自绘弹层，完全掌控样式。
    @State private var showWhiteNoiseMenu = false

    var body: some View {
        HStack(spacing: 0) {
            durationButton
            toolbarDivider
            taskButton
            toolbarDivider
            whiteNoiseButton
            toolbarDivider
            statsButton
        }
        .cardStyle()
        .sheet(isPresented: $showStats) {
            statsSheetContent
                // 2026-11-22：仪表盘固定高度（用户要求）。560 留白过大→470 偏紧→500 微调；
                // 显式显示拖拽指示条（单一固定 detent 下系统默认隐藏）。
                .presentationDetents([.height(500)])
                .presentationDragIndicator(.visible)
        }
        // 自绘白噪音弹层：盖在工具条之上，锚定底部向上展开
        .overlay(alignment: .bottom) {
            if showWhiteNoiseMenu {
                whiteNoiseMenuOverlay
            }
        }
    }

    // MARK: - 时长（Menu，选中立即启动）

    private var durationButton: some View {
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
            toolbarItem(icon: "timer", title: L10n.shared.时长, active: false)
        }
        .accessibilityIdentifier("toolbarDurationButton")
        .accessibilityLabel(L10n.shared.时长)
        .accessibilityHint(L10n.shared.选择后立即开始专注)
    }

    private var durationOptions: [TimeInterval] {
        switch focusViewModel.activePhase {
        case .focus:      return AppConstants.focusDurationOptions
        case .shortBreak: return AppConstants.shortBreakOptions
        case .longBreak:  return AppConstants.longBreakOptions
        }
    }

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

    /// 与 DurationChipsView.applyAndStart 完全一致：写默认值 → abandon 旧会话 → 保留轮次 → 启动
    private func applyAndStart(duration: TimeInterval) {
        HapticManager.shared.selectionFeedback()
        let phase = focusViewModel.activePhase
        switch phase {
        case .focus:      focusViewModel.applyFocusDuration(duration)
        case .shortBreak: focusViewModel.applyShortBreakDuration(duration)
        case .longBreak:  focusViewModel.applyLongBreakDuration(duration)
        }
        let preservedRound = focusViewModel.currentRoundIndex
        if focusViewModel.timerState != .idle {
            focusViewModel.abandonSession()
        }
        focusViewModel.startFocus(phase: phase, durationOverride: duration)
        focusViewModel.restoreRoundIndex(preservedRound)
    }

    // MARK: - 任务（Menu，选中即绑定）

    private var taskButton: some View {
        Menu {
            Button {
                focusViewModel.selectTask(nil)
            } label: {
                if selectedTask == nil {
                    Label(L10n.shared.无关联任务, systemImage: "checkmark")
                } else {
                    Text(L10n.shared.无关联任务)
                }
            }
            Divider()
            ForEach(taskViewModel.activeTasks) { task in
                Button {
                    focusViewModel.selectTask(task)
                } label: {
                    if selectedTask?.id == task.id {
                        Label(task.title, systemImage: "checkmark")
                    } else {
                        Text(task.title)
                    }
                }
            }
        } label: {
            toolbarItem(icon: "link", title: selectedTask?.title ?? L10n.shared.任务, active: selectedTask != nil)
        }
        .accessibilityIdentifier("toolbarTaskButton")
        .accessibilityLabel(taskAccessibilityLabel)
    }

    private var selectedTask: Task? {
        guard let task = focusViewModel.selectedTask, !task.isDeleted else { return nil }
        return task
    }

    private var taskAccessibilityLabel: String {
        if let task = selectedTask {
            return L10n.shared.关联任务 + "，" + task.title
        }
        return L10n.shared.关联任务
    }

    // MARK: - 白噪音（点击直接弹菜单：顶部对勾开关 + 下方各音效）
    // 2026-11-22 简化：原「sheet 内嵌 WhiteNoiseSliderCard（开关 + 音效抽屉两层）」改为单层菜单。
    // 复用同一套 ViewModel 逻辑（toggleWhiteNoise / setWhiteNoiseType），功能 100% 保留、层级更浅。

    private var whiteNoiseButton: some View {
        Button {
            HapticManager.shared.selectionFeedback()
            withAnimation(.easeOut(duration: 0.18)) { showWhiteNoiseMenu.toggle() }
        } label: {
            toolbarItem(
                // 开关状态读偏好 isWhiteNoiseEnabled（非运行时播放态 isWhiteNoiseOn）：
                // 未开始专注时打开开关也应显示"开"，只是不出声（2026-11-22 语义）。
                // 关闭态原用 "speaker.waves"：该 SF Symbol 在当前系统渲染为空（只显示文字），
                // 换成确定可用的 "speaker.wave.2"（iOS 13+）；开启态保留 "waveform"。
                icon: focusViewModel.isWhiteNoiseEnabled ? "waveform" : "speaker.wave.2",
                title: L10n.shared.白噪音,
                active: focusViewModel.isWhiteNoiseEnabled
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("toolbarWhiteNoiseButton")
        .accessibilityLabel(L10n.shared.白噪音)
        .accessibilityHint(focusViewModel.isWhiteNoiseEnabled ? L10n.shared.白噪音开 : L10n.shared.白噪音关)
    }

    // MARK: - 白噪音自绘弹层（系统 Menu 强制 tint 无法自定义颜色，故自绘）
    // 选中项：红色高亮文字 + 加粗 + 实心圆勾；未选中项：灰色字 + 常规字重 + 原音效图标。

    private var whiteNoiseMenuOverlay: some View {
        // v1.3.5 iPad 复查 H2（2026-11-22）：本弹层通过 `.overlay` 挂在工具条上，
        // overlay 收到的 size proposal = 工具条尺寸（约 448×56pt），原 `.frame(maxWidth/Height:.infinity)
        // + .ignoresSafeArea()` 只能填满工具条，点菜单外大片空白关不掉（注释"铺满全屏"与实现不符）。
        // 修法：遮罩用显式整屏 frame（Color.clear 不绘制，尺寸放大无害）+ .fixedSize() 防止被压缩；
        // 菜单卡片仍是遮罩的 .overlay(alignment:.bottom)，因遮罩底边贴屏幕底、工具条也贴 TabBar，
        // 卡片 + padding(.bottom,64) 仍浮在工具条正上方。
        Color.clear
            .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
            .fixedSize()
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeOut(duration: 0.15)) { showWhiteNoiseMenu = false }
            }
            // 无障碍（2026-11-22 审查 H1）：Color.clear + onTapGesture 不产生
            // 可聚焦的无障碍元素，VoiceOver 用户滑入弹层后无直觉关闭入口。
            // 补成带按钮 trait 的关闭元素 + accessibilityAction（不整体 hidden，
            // 也不用 .disabled()，避免读屏无处可点 / 视觉降透明度回归）。
            .accessibilityElement()
            .accessibilityLabel(L10n.shared.关闭菜单)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                withAnimation(.easeOut(duration: 0.15)) { showWhiteNoiseMenu = false }
            }
            // 菜单卡片：锚定遮罩底部（=屏幕底/工具条一带），略微上移避开工具条
            .overlay(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                // 顶部：白噪音总开关行
                Button {
                    HapticManager.shared.selectionFeedback()
                    focusViewModel.toggleWhiteNoise()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: focusViewModel.isWhiteNoiseEnabled ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 18))
                            .foregroundColor(focusViewModel.isWhiteNoiseEnabled ? .focusRed : .secondary)
                        Text(L10n.shared.白噪音)
                            .font(.body.weight(.semibold))
                            .foregroundColor(focusViewModel.isWhiteNoiseEnabled ? .focusRed : .primary)
                        // 撑满整行，使 .contentShape(Rectangle()) 的点击区覆盖右侧空白
                        Spacer(minLength: 8)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("whiteNoiseToggleRow")
                // 2026-11-22 审查 M1/M2：这是开关语义（非选择项），改用 accessibilityValue
                // 表达开/关；label 用「白噪音开关」与第一种音效「白噪音」区分（原两者同名）。
                .accessibilityLabel(L10n.shared.白噪音开关)
                .accessibilityValue(focusViewModel.isWhiteNoiseEnabled ? L10n.shared.白噪音开 : L10n.shared.白噪音关)

                Divider().padding(.horizontal, 12)

                // 下方：各音效
                ForEach(WhiteNoiseType.allCases, id: \.self) { type in
                    let isSelected = focusViewModel.selectedWhiteNoiseType == type
                    Button {
                        HapticManager.shared.selectionFeedback()
                        focusViewModel.setWhiteNoiseType(type)
                        withAnimation(.easeOut(duration: 0.15)) { showWhiteNoiseMenu = false }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : type.systemImage)
                                .font(.system(size: 17))
                                .frame(width: 22, alignment: .center)
                                .foregroundColor(isSelected ? .focusRed : .gray)
                            Text(type.localizedName)
                                .font(isSelected ? .body.weight(.semibold) : .body)
                                .foregroundColor(isSelected ? .focusRed : .gray)
                            Spacer(minLength: 8)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(type.localizedName)
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                    // 2026-11-22 审查 L2：补齐与 WhiteNoiseSliderCard 一致的选中/选择提示
                    .accessibilityHint(isSelected ? L10n.shared.当前已选环境音 : L10n.shared.选择此环境音)
                }
            }
            .padding(.vertical, 8)
            .frame(width: 240)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(uiColor: .systemGray6))
                    .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
            )
            .padding(.bottom, 64) // 抬离工具条
            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)))
            }
        // 注：不设 accessibilityViewIsModal —— 该语义会把 VoiceOver 焦点锁在弹层内，
        // 一旦关闭入口失效用户将被困；遮罩「关闭菜单」按钮已提供可达的退出路径。
        // 注：遮罩已用显式整屏 frame 撑开，勿再加 .frame(maxWidth/Height:.infinity)
        // 覆盖回工具条尺寸（那正是 H2 的原始 bug）。
    }

    // MARK: - 统计（sheet 内嵌今日三项）

    private var statsButton: some View {
        Button {
            showStats = true
        } label: {
            toolbarItem(icon: "chart.bar.fill", title: L10n.shared.统计, active: false)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("toolbarStatsButton")
        .accessibilityLabel(L10n.shared.统计)
        .accessibilityHint(L10n.shared.今日概览)
    }

    private var statsSheetContent: some View {
        // 2026-11-22 重设计：从单薄的三列数字卡换成今日概览仪表盘
        TodayOverviewSheetView()
    }

    // MARK: - 通用按钮外观（系统 Button/Label 组合，不自绘控件）

    private func toolbarItem(icon: String, title: String, active: Bool) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .medium))
                .foregroundColor(active ? .focusRed : .secondary)
                .frame(height: 22)
            Text(title)
                .font(.caption2)
                .foregroundColor(active ? .focusRed : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .contentShape(Rectangle())
    }

    private var toolbarDivider: some View {
        Rectangle()
            .fill(Color(.separator).opacity(0.5))
            .frame(width: 1, height: 30)
    }
}

#if DEBUG
struct FocusToolbarView_Previews: PreviewProvider {
    static var previews: some View {
        FocusToolbarView()
            .environmentObject(AppDependency().focusViewModel)
            .environmentObject(AppDependency().taskViewModel)
            .environmentObject(AppDependency().statsViewModel)
            .environmentObject(L10n.shared)
            .padding()
    }
}
#endif

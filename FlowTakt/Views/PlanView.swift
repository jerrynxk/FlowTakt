import SwiftUI

// MARK: - 计划视图（任务 + 日历）

struct PlanView: View {
    @EnvironmentObject var taskViewModel: TaskViewModel
    @EnvironmentObject var scheduleViewModel: ScheduleViewModel
    @EnvironmentObject var l10n: L10n
    @EnvironmentObject var appDependency: AppDependency

    @State private var selectedTab: PlanTab = .task

    enum PlanTab: CaseIterable {
        case task
        case calendar
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                ForEach(PlanTab.allCases, id: \.self) { tab in
                    switch tab {
                    case .task:     Text(L10n.shared.任务).tag(tab)
                    case .calendar: Text(L10n.shared.日程).tag(tab)
                    }
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            // 无障碍（2026-10-14）：分段控件补用途标签
            .accessibilityLabel(L10n.shared.plan)
            // 与其它 Tab 顶部分段控件统一标识（UI 测试断言选中态依赖它）
            .accessibilityIdentifier("topTabPicker")

            switch selectedTab {
            case .task:
                TaskListView()
            case .calendar:
                ScheduleView()
                    .environmentObject(taskViewModel)
                    .environmentObject(appDependency)
            }
        }
        // 消费来自 Widget 深链的待应用子页（如跳转到「日程」）
        .onReceive(appDependency.$pendingPlanTab) { pending in
            if let pending {
                selectedTab = pending
                appDependency.pendingPlanTab = nil
            }
        }
        // 左右滑动切换「任务 / 日程」（2026-11-02 用户需求）
        // 与专注页的「专注 / 短休 / 长休」保持同一交互语言，复用同一手势实现。
        //
        // 阈值说明：任务列表行本身带 swipeActions（左滑完成 / 右滑删除），
        // 若阈值过低，横滑某一行时页面会连带切走。这里把触发距离提高到 90pt，
        // 明显大于行内操作所需位移，只有「整页横扫」才会切换。
        .swipeToSwitchTab(
            triggerDistance: 90,
            onSwipeLeft: { switchTab(by: 1) },
            onSwipeRight: { switchTab(by: -1) }
        )
        // v1.3.4p：iPad 全量适配 — SwiftUI NavigationSplitView detail 内 frame(maxWidth:) 被撑开，
        // List/Picker 在 iPad 上保持自然宽度（参考邮件/备忘录的 iPad 设计）
    }

    /// 按方向切换子页（向左 = 下一个，向右 = 上一个），边界处夹紧不回环
    private func switchTab(by direction: Int) {
        let order = PlanTab.allCases
        guard let idx = order.firstIndex(of: selectedTab) else { return }
        let newIdx = min(max(idx + direction, 0), order.count - 1)
        guard newIdx != idx else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedTab = order[newIdx]
        }
    }
}

#Preview {
    PlanView()
        .environmentObject(TaskViewModel(
            taskService: TaskService(persistenceController: .shared),
            persistenceController: .shared
        ))
        .environmentObject(ScheduleViewModel(
            scheduleService: ScheduleService(persistenceController: .shared),
            persistenceController: .shared
        ))
        .environmentObject(AppDependency())
        .environmentObject(L10n.shared)
}

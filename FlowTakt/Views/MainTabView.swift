import SwiftUI

// MARK: - 主标签页视图

struct MainTabView: View {
    @EnvironmentObject var focusViewModel: FocusViewModel
    @EnvironmentObject var taskViewModel: TaskViewModel
    @EnvironmentObject var statsViewModel: StatsViewModel
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @EnvironmentObject var achievementViewModel: AchievementViewModel
    @EnvironmentObject var scheduleViewModel: ScheduleViewModel
    @EnvironmentObject var habitViewModel: HabitViewModel
    @EnvironmentObject var timeRecordViewModel: TimeRecordViewModel
    @EnvironmentObject var l10n: L10n
    @EnvironmentObject var appDependency: AppDependency
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                // iPad / 常规宽度：侧边栏主从布局（NavigationSplitView）
                NavigationSplitView {
                    sidebar
                } detail: {
                    detailView
                }
            } else {
                // iPhone / 紧凑宽度：底部标签栏
                // 关键：.id(l10n.appLanguage) 强制语言切换时重建整个视图树。
                // SwiftUI 的 Menu / Picker(.menu) 菜单内容不响应 environment 变化刷新（已知问题），
                // 必须通过 id 变更强制重建才能让所有菜单文字跟随语言切换。
                TabView(selection: $appDependency.selectedMainTab) {
                    // 专注
                    FocusView()
                        .tabItem {
                            Label(L10n.shared.focus, systemImage: "clock.arrow.circlepath")
                        }
                        .tag(MainTab.focus)

                    // 计划（任务 + 日历）
                    PlanView()
                        .tabItem {
                            Label(L10n.shared.plan, systemImage: "calendar")
                        }
                        .tag(MainTab.plan)

                    // 习惯（习惯 + 计时）
                    HabitTrackView()
                        .tabItem {
                            Label(L10n.shared.habits, systemImage: "checkmark.circle.fill")
                        }
                        .tag(MainTab.habit)

                    // 统计（统计 + 成就）
                    StatsOverviewView()
                        .tabItem {
                            Label(L10n.shared.stats, systemImage: "chart.bar.fill")
                        }
                        .tag(MainTab.stats)

                    // 设置
                    SettingsView()
                        .tabItem {
                            Label(L10n.shared.settings, systemImage: "gearshape.fill")
                        }
                        .tag(MainTab.settings)
                }
            }
        }
        .tint(.focusRed)
        .preferredColorScheme(settingsViewModel.preferredColorScheme)
        .id(l10n.appLanguage)
    }

    // MARK: - iPad 侧边栏

    private var sidebar: some View {
        // iPad 侧边栏：直接用 Button 设置 selectedMainTab，联动切换 detailView。
        // 注：iOS 上 List(selection:) 的 builder 重载不可用（仅 macOS），
        // 且 NavigationLink(value:) 需配合 .navigationDestination 才能驱动详情，
        // 而本视图的 detail 由 selectedMainTab 的 switch 驱动，故用 Button 最直接可靠。
        List {
            sidebarItem(.focus, title: L10n.shared.focus, icon: "clock.arrow.circlepath")
            sidebarItem(.plan, title: L10n.shared.plan, icon: "calendar")
            sidebarItem(.habit, title: L10n.shared.habits, icon: "checkmark.circle.fill")
            sidebarItem(.stats, title: L10n.shared.stats, icon: "chart.bar.fill")
            sidebarItem(.settings, title: L10n.shared.settings, icon: "gearshape.fill")
        }
        .navigationTitle("FlowTakt")
        .listStyle(.sidebar)
    }

    private func sidebarItem(_ tab: MainTab, title: String, icon: String) -> some View {
        Button {
            appDependency.selectedMainTab = tab
        } label: {
            Label(title, systemImage: icon)
        }
        .foregroundStyle(appDependency.selectedMainTab == tab ? Color.focusRed : Color.primary)
        // v1.3.4p：iPad 无障碍补全 — 侧边栏选中项朗读「已选」（iPhone TabBar 自带，iPad sidebar 需手动补）
        .accessibilityAddTraits(appDependency.selectedMainTab == tab ? [.isSelected] : [])
    }

    @ViewBuilder
    private var detailView: some View {
        // v1.3.4p：iPad 适配说明 —
        // 专注页自处理 maxWidth 640 + sizeClass 垂直布局；设置页 SwiftUI Form 自动居中；
        // 计划/习惯/统计：NavigationSplitView detail 内 frame(maxWidth:) 被撑开（SwiftUI 限制），
        // List/Picker 保持 iPad 自然宽度（参考邮件/备忘录 iPad 设计）
        switch appDependency.selectedMainTab {
        case .focus:    FocusView()
        case .plan:     PlanView()
        case .habit:    HabitTrackView()
        case .stats:    StatsOverviewView()
        case .settings: SettingsView()
        }
    }
}

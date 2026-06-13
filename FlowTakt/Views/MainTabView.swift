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

    var body: some View {
        TabView {
            // 专注
            FocusView()
                .environmentObject(focusViewModel)
                .environmentObject(taskViewModel)
                .environmentObject(statsViewModel)
                .environmentObject(settingsViewModel)
                .tabItem {
                    Label(L10n.shared.focus, systemImage: "clock.arrow.circlepath")
                }

            // 计划（任务 + 日历）
            PlanView()
                .environmentObject(taskViewModel)
                .environmentObject(scheduleViewModel)
                .tabItem {
                    Label(L10n.shared.plan, systemImage: "calendar")
                }

            // 习惯（习惯 + 计时）
            HabitTrackView()
                .environmentObject(habitViewModel)
                .environmentObject(timeRecordViewModel)
                .environmentObject(taskViewModel)
                .tabItem {
                    Label(L10n.shared.habits, systemImage: "checkmark.circle.fill")
                }

            // 统计（统计 + 成就）
            StatsOverviewView()
                .environmentObject(statsViewModel)
                .environmentObject(achievementViewModel)
                .tabItem {
                    Label(L10n.shared.stats, systemImage: "chart.bar.fill")
                }

            // 设置
            SettingsView()
                .environmentObject(settingsViewModel)
                .tabItem {
                    Label(L10n.shared.settings, systemImage: "gearshape.fill")
                }
        }
        .tint(.focusRed)
    }
}

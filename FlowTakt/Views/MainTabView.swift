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

    var body: some View {
        TabView {
            // 专注
            FocusView()
                .environmentObject(focusViewModel)
                .environmentObject(taskViewModel)
                .environmentObject(statsViewModel)
                .environmentObject(settingsViewModel)
                .tabItem {
                    Label("专注", systemImage: "clock.arrow.circlepath")
                }

            // 任务
            TaskListView()
                .environmentObject(taskViewModel)
                .tabItem {
                    Label("任务", systemImage: "list.bullet")
                }

            // 日历
            ScheduleView()
                .environmentObject(scheduleViewModel)
                .environmentObject(taskViewModel)
                .tabItem {
                    Label("日历", systemImage: "calendar")
                }

            // 习惯
            HabitListView()
                .environmentObject(habitViewModel)
                .tabItem {
                    Label("习惯", systemImage: "checkmark.circle.fill")
                }

            // 计时
            TimeRecordView()
                .environmentObject(timeRecordViewModel)
                .environmentObject(taskViewModel)
                .tabItem {
                    Label("计时", systemImage: "stopwatch.fill")
                }

            // 统计
            StatsView()
                .environmentObject(statsViewModel)
                .tabItem {
                    Label("统计", systemImage: "chart.bar.fill")
                }

            // 成就
            AchievementListView()
                .environmentObject(achievementViewModel)
                .tabItem {
                    Label("成就", systemImage: "trophy.fill")
                }

            // 设置
            SettingsView()
                .environmentObject(settingsViewModel)
                .tabItem {
                    Label("设置", systemImage: "gearshape.fill")
                }
        }
        .tint(.focusRed)
    }
}

import SwiftUI

@main
struct FlowTaktApp: App {
    @StateObject private var dependency = AppDependency()

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(dependency)
                .environmentObject(dependency.focusViewModel)
                .environmentObject(dependency.taskViewModel)
                .environmentObject(dependency.statsViewModel)
                .environmentObject(dependency.settingsViewModel)
                .environmentObject(dependency.achievementViewModel)
                .environmentObject(dependency.scheduleViewModel)
                .environmentObject(dependency.habitViewModel)
                .environmentObject(dependency.timeRecordViewModel)
        }
    }
}

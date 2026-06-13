import SwiftUI

@main
struct FlowTaktApp: App {
    @StateObject private var dependency = AppDependency()
    @StateObject private var l10n = L10n.shared
    @Environment(\.scenePhase) private var scenePhase

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
                .environmentObject(l10n)
                .environment(\.locale, Locale(identifier: l10n.appLanguage))
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                dependency.timerManager.syncFromBackground()
                dependency.audioService.configureAudioSession()
            }
        }
    }
}

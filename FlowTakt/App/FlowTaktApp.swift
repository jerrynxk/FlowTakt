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
                .task {
                    // 应用首次启动时初始化通知权限和 iCloud 同步
                    dependency.setupApp()
                }
                .onOpenURL { url in
                    dependency.handleDeepLink(url)
                }
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                dependency.timerManager.syncFromBackground()
                dependency.audioService.configureAudioSession()
            }
        }
    }
}

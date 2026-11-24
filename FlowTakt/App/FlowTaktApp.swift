import SwiftUI

@main
struct FlowTaktApp: App {
    // 修复（2026-10-14 P2）：BGTask 必须在 didFinishLaunchingWithOptions 内注册，
    // SwiftUI 生命周期下唯一合规接入点就是 UIApplicationDelegateAdaptor
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var dependency = AppDependency()
    @StateObject private var l10n = L10n.shared
    @Environment(\.scenePhase) private var scenePhase

    /// 仅 DEBUG：模拟器/真机都能用环境变量直接开始一次专注会话，便于验证灵动岛：
    /// `SIMCTL_CHILD_FLOWTAKT_AUTOSTART_FOCUS=1 xcrun simctl launch <UDID> com.flowtakt.FlowTakt`
    /// （Release 构建不含此逻辑）
    private func autostartFocusIfRequested() {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["FLOWTAKT_AUTOSTART_FOCUS"] == "1" else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            AppDependency.shared?.focusViewModel.startFocus(phase: .focus)
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .onAppear { autostartFocusIfRequested() }
                .environmentObject(dependency)
                .environmentObject(dependency.focusViewModel)
                .environmentObject(dependency.taskViewModel)
                .environmentObject(dependency.tagViewModel)
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
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                dependency.timerManager.syncFromBackground()
                dependency.audioService.configureAudioSession()
            }
        }
    }
}

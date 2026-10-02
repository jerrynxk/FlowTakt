import SwiftUI

// MARK: - AppearanceSettingsSection

/// 外观设置：深色 / 浅色 / 跟随系统
struct AppearanceSettingsSection: View {
    @ObservedObject var viewModel: SettingsViewModel
    @EnvironmentObject var l10n: L10n

    private let options = ["system", "light", "dark"]

    var body: some View {
        Section(L10n.shared.外观) {
            Picker(selection: $viewModel.colorSchemeOption) {
                Label(L10n.shared.跟随系统, systemImage: "circle.lefthalf.filled")
                    .tag("system")
                Label(L10n.shared.浅色模式, systemImage: "sun.max.fill")
                    .tag("light")
                Label(L10n.shared.深色模式, systemImage: "moon.fill")
                    .tag("dark")
            } label: {
                // 补图标（与其它设置项一致：Label + systemImage）
                Label(L10n.shared.颜色主题, systemImage: "paintpalette.fill")
            }
        }
    }
}

#Preview {
    Form {
        AppearanceSettingsSection(viewModel: SettingsViewModel(syncService: MockSyncService()))
    }
    .environmentObject(L10n.shared)
}

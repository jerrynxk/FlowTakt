import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var viewModel: SettingsViewModel
    @EnvironmentObject var l10n: L10n
    @State private var resetAlert: ResetAlertType?

    enum ResetAlertType: Identifiable {
        case confirm, success, failure
        var id: Self { self }
    }

    var body: some View {
        NavigationStack {
            Form {
                TimerSettingsSection(viewModel: viewModel)
                SoundSettingsSection(viewModel: viewModel)
                LanguageSettingsSection(viewModel: viewModel)
                SyncSettingsSection(viewModel: viewModel, showResetAlert: $resetAlert)
                AboutSection()
            }
            .navigationTitle(L10n.shared.设置)
            .navigationBarTitleDisplayMode(.inline)
            .alert(item: $resetAlert) { type in
                switch type {
                case .confirm:
                    return Alert(
                        title: Text(L10n.shared.重置数据库),
                        message: Text(L10n.shared.重置数据库确认提示),
                        primaryButton: .destructive(Text(L10n.shared.确认重置)) {
                            // Phase 0: 先通知所有 VM 清空数据（store 仍在，ForEach diff 安全）
                            NotificationCenter.default.post(name: .databaseWillReset, object: nil)
                            // Phase 1: 等待一个 run loop 让 SwiftUI 处理 @Published 更新
                            // Phase 2: 再执行 store 销毁重建 + 发送 databaseDidReset 触发重新加载
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                let success = viewModel.resetDatabase()
                                resetAlert = success ? .success : .failure
                            }
                        },
                        secondaryButton: .cancel(Text(L10n.shared.取消))
                    )
                case .success:
                    return Alert(
                        title: Text(L10n.shared.重置成功),
                        message: Text(L10n.shared.重置数据库成功提示),
                        dismissButton: .default(Text(L10n.shared.好的))
                    )
                case .failure:
                    return Alert(
                        title: Text(L10n.shared.重置失败),
                        message: Text(L10n.shared.重置数据库失败提示),
                        dismissButton: .default(Text(L10n.shared.好的))
                    )
                }
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(SettingsViewModel(syncService: MockSyncService()))
}

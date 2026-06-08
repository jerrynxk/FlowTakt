import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var viewModel: SettingsViewModel
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
                SyncSettingsSection(viewModel: viewModel, showResetAlert: $resetAlert)
                AboutSection()
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .alert(item: $resetAlert) { type in
                switch type {
                case .confirm:
                    return Alert(
                        title: Text("重置数据库"),
                        message: Text("此操作将清空所有任务、专注记录、成就和标签数据，且无法恢复。确定要继续吗？"),
                        primaryButton: .destructive(Text("确认重置")) {
                            let success = viewModel.resetDatabase()
                            resetAlert = success ? .success : .failure
                        },
                        secondaryButton: .cancel(Text("取消"))
                    )
                case .success:
                    return Alert(
                        title: Text("重置成功"),
                        message: Text("数据库已重置为空，所有数据已被清空。"),
                        dismissButton: .default(Text("好的"))
                    )
                case .failure:
                    return Alert(
                        title: Text("重置失败"),
                        message: Text("数据库重置过程中发生错误，请尝试重启应用后重试。"),
                        dismissButton: .default(Text("好的"))
                    )
                }
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(SettingsViewModel())
}

import SwiftUI

struct SyncSettingsSection: View {
    @ObservedObject var viewModel: SettingsViewModel
    @Binding var showResetAlert: SettingsView.ResetAlertType?

    var body: some View {
        Section {
            Toggle(isOn: $viewModel.iCloudSyncEnabled) {
                Label("iCloud 同步", systemImage: "icloud.fill")
            }

            Toggle(isOn: $viewModel.dailyReminderEnabled) {
                Label("每日提醒", systemImage: "bell.fill")
            }

            if viewModel.dailyReminderEnabled {
                HStack {
                    Label("提醒时间", systemImage: "clock")
                    Spacer()
                    Text(formattedReminderTime)
                        .foregroundColor(.secondary)
                }
            }

            Button(role: .destructive) {
                showResetAlert = .confirm
            } label: {
                Label("重置数据库", systemImage: "trash.fill")
            }
        } header: {
            Text("同步与数据")
        } footer: {
            Text("重置数据库将清空所有任务、专注记录、成就和标签数据，此操作无法撤销。")
        }
    }

    private var formattedReminderTime: String {
        let hour = viewModel.dailyReminderTime.hour ?? 9
        let minute = viewModel.dailyReminderTime.minute ?? 0
        return String(format: "%02d:%02d", hour, minute)
    }
}

#Preview {
    Form {
        SyncSettingsSection(
            viewModel: SettingsViewModel(),
            showResetAlert: .constant(nil)
        )
    }
}

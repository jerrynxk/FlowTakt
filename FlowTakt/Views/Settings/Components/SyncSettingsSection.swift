import SwiftUI

struct SyncSettingsSection: View {
    @EnvironmentObject var l10n: L10n

    @ObservedObject var viewModel: SettingsViewModel
    @Binding var showResetAlert: SettingsView.ResetAlertType?

    var body: some View {
        Section {
            Toggle(isOn: $viewModel.iCloudSyncEnabled) {
                Label(L10n.shared.iCloud同步, systemImage: "icloud.fill")
            }

            Toggle(isOn: $viewModel.dailyReminderEnabled) {
                Label(L10n.shared.每日提醒, systemImage: "bell.fill")
            }

            if viewModel.dailyReminderEnabled {
                HStack {
                    Label(L10n.shared.提醒时间, systemImage: "clock")
                    Spacer()
                    Text(formattedReminderTime)
                        .foregroundColor(.secondary)
                }
            }

            Button(role: .destructive) {
                showResetAlert = .confirm
            } label: {
                Label(L10n.shared.重置数据库, systemImage: "trash.fill")
            }
        } header: {
            Text(L10n.shared.同步与数据)
        } footer: {
            Text(L10n.shared.重置数据库提示)
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

import SwiftUI

struct SyncSettingsSection: View {
    @EnvironmentObject var l10n: L10n

    @ObservedObject var viewModel: SettingsViewModel
    @Binding var showResetAlert: SettingsView.ResetAlertType?
    @State private var syncMessage: String?

    var body: some View {
        Section {
            Toggle(isOn: $viewModel.iCloudSyncEnabled) {
                Label(L10n.shared.iCloud同步, systemImage: "icloud.fill")
            }
            .onChange(of: viewModel.iCloudSyncEnabled) { newValue in
                if newValue {
                    viewModel.forceSync()
                }
            }

            // 手动同步按钮
            Button {
                if viewModel.iCloudSyncEnabled {
                    viewModel.forceSync()
                    syncMessage = L10n.shared.同步已触发
                } else {
                    syncMessage = L10n.shared.同步需先开启iCloud
                }
                // 3 秒后自动清除提示
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    syncMessage = nil
                }
            } label: {
                Label(L10n.shared.立即同步, systemImage: "arrow.triangle.2.circlepath")
            }

            // 同步反馈
            if let message = syncMessage {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
            Text(L10n.shared.iCloud同步说明)
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
            viewModel: SettingsViewModel(syncService: MockSyncService()),
            showResetAlert: .constant(nil)
        )
    }
}

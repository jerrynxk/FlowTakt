import SwiftUI
import WidgetKit

struct ReminderSettingsSection: View {
    @EnvironmentObject var l10n: L10n
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Section {
            // 通知权限状态
            HStack {
                Label(L10n.shared.通知权限, systemImage: "bell.badge.fill")
                Spacer()
                Text(viewModel.notificationStatusText)
                    .foregroundColor(viewModel.isNotificationAuthorized ? .green : .secondary)
            }

            if !viewModel.isNotificationAuthorized {
                Button {
                    viewModel.openSystemSettings()
                } label: {
                    Label(L10n.shared.去设置, systemImage: "arrow.up.right.square")
                }
            }

            // 后台 App 刷新状态（系统设置项，仅可读取）
            HStack {
                Label(L10n.shared.后台App刷新, systemImage: "arrow.clockwise")
                Spacer()
                Text(viewModel.backgroundRefreshStatusText)
                    .foregroundColor(.secondary)
            }

            // 每周日专注周报
            Toggle(isOn: $viewModel.weeklyReportEnabled) {
                Label(L10n.shared.每周日周报, systemImage: "calendar.badge.clock")
            }
            Text(L10n.shared.每周日周报说明)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 32)

            // 每日习惯打卡提醒
            Toggle(isOn: $viewModel.habitReminderEnabled) {
                Label(L10n.shared.习惯打卡提醒, systemImage: "checkmark.seal.fill")
            }
            if viewModel.habitReminderEnabled {
                DatePicker(
                    L10n.shared.提醒时间,
                    selection: Binding(
                        get: { viewModel.habitReminderTime.toDate() },
                        set: { viewModel.habitReminderTime = $0.toDateComponents() }
                    ),
                    displayedComponents: .hourAndMinute
                )
                .padding(.leading, 32)
            }

            // 立即刷新小组件（便于调试与即时生效）
            Button {
                WidgetCenter.shared.reloadAllTimelines()
            } label: {
                Label(L10n.shared.刷新小组件, systemImage: "widget.large.badge.plus")
            }
        } header: {
            Text(L10n.shared.提醒与通知)
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.shared.后台刷新说明)
                Text(L10n.shared.添加小组件说明)
            }
        }
    }
}

#Preview {
    Form {
        ReminderSettingsSection(viewModel: SettingsViewModel(syncService: MockSyncService()))
    }
    .environmentObject(L10n.shared)
}

// MARK: - 时间绑定辅助（DateComponents ↔ Date）

private extension DateComponents {
    func toDate() -> Date {
        Calendar.current.date(from: self) ?? Date()
    }
}

private extension Date {
    func toDateComponents() -> DateComponents {
        Calendar.current.dateComponents([.hour, .minute], from: self)
    }
}

import SwiftUI

struct SyncSettingsSection: View {
    @EnvironmentObject var l10n: L10n

    @ObservedObject var viewModel: SettingsViewModel
    @Binding var showResetAlert: SettingsView.ResetAlertType?
    @State private var syncMessage: String?
    /// 手动同步进行中（按钮禁用，防连点）
    @State private var syncInFlight = false

    var body: some View {
        Section {
            Toggle(isOn: $viewModel.iCloudSyncEnabled) {
                Label(L10n.shared.iCloud同步, systemImage: "icloud.fill")
            }
            // 修复（2026-11-19）：开关打开时不再立即 forceSync —— applyCloudKitConfiguration
            // 正在异步重载 store（isStoreReady=false），此刻同步必返回「尚未就绪」假报错。
            // 挂载成功后系统自动同步，无需手动触发。

            // 同步状态（用户反馈 2026-11-19）：默认自动同步，此处如实展示当前是「自动同步中」
            // 还是「账户不可用 / 已关闭」，避免开关为开就被误读为「已同步完成」
            HStack {
                Label(L10n.shared.同步状态, systemImage: viewModel.cloudSyncStatusIcon)
                    .labelStyle(.titleAndIcon)
                Spacer()
                Text(viewModel.cloudSyncStatusText)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            .font(.footnote)
            .accessibilityElement(children: .combine)

            // 手动同步按钮
            // 用户反馈 2026-11-17：如实展示同步结果，不再无条件显示「同步请求已发送」
            // 用户反馈 2026-11-19：改用 syncNow —— 先刷新账户状态快照再同步，
            // 修复「重新登录 iCloud 后按钮恒报账户不可用」的状态过期问题
            Button {
                guard !syncInFlight else { return }
                syncInFlight = true
                viewModel.syncNow { outcome in
                    syncInFlight = false
                    syncMessage = Self.message(for: outcome)
                    // 结果提示停留 4 秒（比旧的 3 秒略长，便于读清"后台自动导入"的说明）
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                        syncMessage = nil
                    }
                }
            } label: {
                Label(L10n.shared.立即同步, systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(syncInFlight)

            // 同步反馈
            if let message = syncMessage {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // iCloud 同步切换失败的具体原因（2026-10-15 审查 P0-1：禁止笼统报错，
            // 失败时开关已自动回滚，此处如实展示原因）
            if let syncError = viewModel.cloudSyncError {
                Text(syncError)
                    .font(.caption)
                    .foregroundColor(.focusRed)
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
            // 用户反馈 2026-11-19：说明「默认自动同步」这一事实，避免用户以为还要手动上传下载
            Text(L10n.shared.iCloud自动同步说明)
        }
    }

    /// 把同步真实结果转成如实文案（判据收口在此处，不在按钮里各打补丁）
    private static func message(for outcome: SyncOutcome) -> String {
        switch outcome {
        case .savedLocalChanges:
            return L10n.shared.同步结果已保存
        case .noLocalChanges:
            return L10n.shared.同步结果无本地变更
        case .syncDisabled:
            return L10n.shared.同步需先开启iCloud
        case .accountUnavailable:
            return L10n.shared.同步结果账户不可用
        case .notMounted:
            return L10n.shared.同步结果未挂载
        case .failed(let reason):
            return L10n.shared.同步结果失败(reason)
        }
    }

    private var formattedReminderTime: String {
        let hour = viewModel.dailyReminderTime.hour ?? 9
        let minute = viewModel.dailyReminderTime.minute ?? 0
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        // 审查修复（2026-08-12）：改用 DateFormatter 跟随 locale（12/24 小时制），替代硬编码 "%02d:%02d"
        let date = Calendar.current.date(from: comps) ?? Date()
        return Self.timeFormatter.string(from: date)
    }

    /// 时间格式化器（static 缓存，跟随 locale）
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()
}

#Preview {
    Form {
        SyncSettingsSection(
            viewModel: SettingsViewModel(syncService: MockSyncService()),
            showResetAlert: .constant(nil)
        )
    }
    .environmentObject(L10n.shared)
}

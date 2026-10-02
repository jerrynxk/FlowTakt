import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - 设置页统一红色图标 LabelStyle
// v1.3.4m：设置页所有菜单条目图标统一 focusRed（文字保持默认色）。
// 通过 LabelStyle 作用于整个 Form，避免逐条手工指定颜色且不遗漏新增条目。

struct SettingsRedIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.icon
                .foregroundColor(.focusRed)
                // 无障碍修复（2026-08-12）：图标不单独朗读，只读文字标题
                .accessibilityHidden(true)
            configuration.title
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var viewModel: SettingsViewModel
    @EnvironmentObject var l10n: L10n
    @State private var resetAlert: ResetAlertType?
    @State private var exportURLs: [URL] = []
    @State private var showExportShare = false
    @State private var backupURLs: [URL] = []
    @State private var showBackupShare = false
    @State private var showRestoreConfirm = false
    @State private var showRestoreImporter = false

    /// 单一 alert 状态：覆盖重置确认/结果、导出失败、恢复结果，
    /// 避免同一视图链多个 .alert 修饰符导致 iOS 16+ 只有最后一个生效
    enum ResetAlertType: Identifiable {
        case confirm, success, failure, exportFailed, restoreSuccess, restoreFailure
        var id: Self { self }
    }

    /// 根据当前 alert 状态派生标题
    private var alertTitle: Text {
        switch resetAlert {
        case .confirm: return Text(L10n.shared.重置数据库)
        case .success: return Text(L10n.shared.重置成功)
        case .failure: return Text(L10n.shared.重置失败)
        case .exportFailed: return Text(L10n.shared.导出失败提示)
        case .restoreSuccess: return Text(L10n.shared.恢复成功提示)
        case .restoreFailure: return Text(L10n.shared.恢复失败提示)
        case nil: return Text("")
        }
    }

    /// alert 显示状态桥接：由 resetAlert != nil 驱动
    private var alertIsPresented: Binding<Bool> {
        Binding(
            get: { resetAlert != nil },
            set: { if !$0 { resetAlert = nil } }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                TimerSettingsSection(viewModel: viewModel)
                SoundSettingsSection(viewModel: viewModel)
                AppearanceSettingsSection(viewModel: viewModel)
                LanguageSettingsSection(viewModel: viewModel)
                SyncSettingsSection(viewModel: viewModel, showResetAlert: $resetAlert)
                ReminderSettingsSection(viewModel: viewModel)

                // 数据导出（CSV）：按实体各出一份文件，系统分享面板打包
                Section {
                    Button {
                        DataExportService.exportAll { urls in
                            if urls.isEmpty {
                                resetAlert = .exportFailed
                            } else {
                                exportURLs = urls
                                showExportShare = true
                            }
                        }
                    } label: {
                        Label(L10n.shared.导出数据, systemImage: "square.and.arrow.up")
                    }
                    .accessibilityLabel(L10n.shared.导出数据)
                    .accessibilityIdentifier("exportCSVButton")
                } header: {
                    Text(L10n.shared.数据导出)
                }

                // 数据备份/恢复（B4）：全量 JSON
                Section {
                    Button {
                        if let url = BackupService(persistenceController: .shared).exportJSON() {
                            backupURLs = [url]
                            showBackupShare = true
                        } else {
                            resetAlert = .exportFailed
                        }
                    } label: {
                        Label(L10n.shared.备份数据, systemImage: "externaldrive.fill")
                    }
                    .accessibilityLabel(L10n.shared.备份数据)
                    .accessibilityIdentifier("backupJSONButton")

                    Button {
                        showRestoreConfirm = true
                    } label: {
                        Label(L10n.shared.恢复数据, systemImage: "arrow.down.doc.fill")
                    }
                    .accessibilityLabel(L10n.shared.恢复数据)
                    .accessibilityIdentifier("restoreDataButton")
                } header: {
                    Text(L10n.shared.数据备份)
                }
                .fileImporter(
                    isPresented: $showRestoreImporter,
                    allowedContentTypes: [.json],
                    allowsMultipleSelection: false
                ) { result in
                    if case .success(let urls) = result, let url = urls.first {
                        let ok = BackupService(persistenceController: .shared).importJSON(from: url)
                        resetAlert = ok ? .restoreSuccess : .restoreFailure
                    }
                }
                .confirmationDialog(L10n.shared.恢复数据, isPresented: $showRestoreConfirm, titleVisibility: .visible) {
                    Button(L10n.shared.恢复数据) { showRestoreImporter = true }
                    Button(L10n.shared.取消, role: .cancel) {}
                } message: {
                    Text(L10n.shared.恢复确认提示)
                }

                AboutSection()
            }
            // v1.3.4m：全部菜单条目图标统一红色（LabelStyle 传播到所有 section）
            .labelStyle(SettingsRedIconLabelStyle())
            .navigationTitle(L10n.shared.设置)
            .navigationBarTitleDisplayMode(.inline)
            // 单一 alert（新版 presenting API）：重置确认/结果与导出失败共用同一状态，避免多 alert 竞争
            .alert(
                alertTitle,
                isPresented: alertIsPresented,
                presenting: resetAlert,
                actions: { type in
                    switch type {
                    case .confirm:
                        Button(L10n.shared.取消, role: .cancel) {}
                        Button(L10n.shared.确认重置, role: .destructive) {
                            // Phase 0: 先通知所有 VM 清空数据（store 仍在，ForEach diff 安全）
                            NotificationCenter.default.post(name: .databaseWillReset, object: nil)
                            // Phase 1: 0.1s 延迟确保 SwiftUI 完成 @Published 更新（清空数组/重置状态）的布局刷新，
                            // 避免在 ViewModel 仍在处理 publisher 事件时触发 CoreData 写冲突。
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                viewModel.resetDatabase { success in
                                    resetAlert = success ? .success : .failure
                                }
                            }
                        }
                    case .success:
                        Button(L10n.shared.好的, role: .cancel) {}
                    case .failure:
                        Button(L10n.shared.好的, role: .cancel) {}
                    case .exportFailed:
                        Button(L10n.shared.好的, role: .cancel) {}
                    case .restoreSuccess:
                        Button(L10n.shared.好的, role: .cancel) {}
                    case .restoreFailure:
                        Button(L10n.shared.好的, role: .cancel) {}
                    }
                },
                message: { type in
                    switch type {
                    case .confirm:
                        Text(L10n.shared.重置数据库确认提示)
                    case .success:
                        Text(L10n.shared.重置数据库成功提示)
                    case .failure:
                        Text(L10n.shared.重置数据库失败提示)
                    case .exportFailed:
                        Text(L10n.shared.导出失败提示)
                    case .restoreSuccess:
                        Text(L10n.shared.恢复成功提示)
                    case .restoreFailure:
                        Text(L10n.shared.恢复失败提示)
                    }
                }
            )
            .sheet(isPresented: $showExportShare) {
                ShareSheet(items: exportURLs)
            }
            .sheet(isPresented: $showBackupShare) {
                ShareSheet(items: backupURLs)
            }
        }
    }
}

// MARK: - 系统分享面板（CSV 文件）

/// 包装 UIActivityViewController，用于分享/保存导出的 CSV 文件。
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

#Preview {
    SettingsView()
        .environmentObject(SettingsViewModel(syncService: MockSyncService()))
}

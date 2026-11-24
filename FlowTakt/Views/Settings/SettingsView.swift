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
    /// 分享面板载荷：URLs + 呈现标记合并为单一状态，避免同一操作两次 @State 更新
    /// 触发两次巨型 Form 重算（2026-10-15，导出/备份共用）
    @State private var sharePayload: SharePayload?
    @State private var showRestoreConfirm = false
    @State private var showRestoreImporter = false

    /// 系统分享面板载荷（Identifiable 供 `.sheet(item:)` 呈现）
    private struct SharePayload: Identifiable {
        let id = UUID()
        let urls: [URL]
    }

    /// 单一 alert 状态：覆盖重置确认/结果、导出失败、恢复结果，
    /// 避免同一视图链多个 .alert 修饰符导致 iOS 16+ 只有最后一个生效
    enum ResetAlertType: Identifiable, Hashable {
        case confirm, success, exportFailed, exportNoData, exportNotReady
        case restoreSuccess, restoreFailure
        /// 本地重置失败：携带该失败原因的具体文案（禁止笼统「重置失败」）
        case resetFailed(String)
        /// 云端清除失败：附带可展示的原因文案（本地数据未改动）
        case cloudPurgeFailed(String)
        var id: Self { self }
    }

    /// 根据当前 alert 状态派生标题
    private var alertTitle: Text {
        switch resetAlert {
        case .confirm: return Text(L10n.shared.重置数据库)
        case .success: return Text(L10n.shared.重置成功)
        case .resetFailed: return Text(L10n.shared.重置失败)
        case .exportFailed: return Text(L10n.shared.导出失败提示)
        case .exportNoData: return Text(L10n.shared.无可导出数据)
        case .exportNotReady: return Text(L10n.shared.数据未就绪)
        case .restoreSuccess: return Text(L10n.shared.恢复成功提示)
        case .restoreFailure: return Text(L10n.shared.恢复失败提示)
        case .cloudPurgeFailed: return Text(L10n.shared.云端清除失败)
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

    /// 统一页头自绘大标题（2026-10-15 审查 P2-Sy1/Sy2）
    /// 规格对齐 TaskListView.titleRow：largeTitle.bold + h1 语义 + 16pt 水平边距
    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(L10n.shared.设置)
                .font(.largeTitle.weight(.bold))
                .accessibilityHeading(.h1)
            Spacer(minLength: 12)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 4)
    }

    var body: some View {
        NavigationStack {
            // 修复（2026-10-15 审查 P2-Sy1/Sy2）：与其他 8 页统一页头规范——
            // 自绘大标题 + accessibilityHeading(.h1)，替代系统 inline 导航栏标题。
            titleRow
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
                        DataExportService.exportAll { result in
                            switch result {
                            case .success(let urls):
                                sharePayload = SharePayload(urls: urls)
                            case .noData:
                                resetAlert = .exportNoData
                            case .storeNotReady:
                                resetAlert = .exportNotReady
                            case .failed:
                                resetAlert = .exportFailed
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
                        // 修复（2026-10-15）：导出已改为后台上下文执行（不阻塞 UI），
                        // 完成后主线程回调再呈现分享面板；失败路径与旧版一致弹「导出失败」
                        BackupService(persistenceController: .shared).exportJSON { url in
                            if let url {
                                sharePayload = SharePayload(urls: [url])
                            } else {
                                resetAlert = .exportFailed
                            }
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
                    guard case .success(let urls) = result, let url = urls.first else {
                        // 用户取消选择属正常路径，不弹错误
                        return
                    }
                    // 修复（2026-10-14，「恢复数据提示恢复失败」）：
                    // fileImporter 返回的是 security-scoped URL，必须显式
                    // startAccessingSecurityScopedResource() 才能读取。
                    // 真机上未开启该作用域时 `Data(contentsOf:)` 抛
                    // NSCocoaErrorDomain Code=257「Operation not permitted」，
                    // 被 importJSON 的 catch 吞掉后一律返回 false → 误报恢复失败。
                    // 模拟器上通常可读，故该问题仅在真机复现。
                    let accessed = url.startAccessingSecurityScopedResource()
                    defer { if accessed { url.stopAccessingSecurityScopedResource() } }

                    let ok = BackupService(persistenceController: .shared).importJSON(from: url)
                    resetAlert = ok ? .restoreSuccess : .restoreFailure
                }
                .confirmationDialog(L10n.shared.恢复数据, isPresented: $showRestoreConfirm, titleVisibility: .visible) {
                    Button(L10n.shared.恢复数据) { showRestoreImporter = true }
                    Button(L10n.shared.取消, role: .cancel) {}
                } message: {
                    Text(L10n.shared.恢复确认提示)
                }

                // 我的其他应用（PinDial 推荐位）：置于「关于」上方，
                // 既符合 iOS「开发者其他产品」惯例，也顺承用户信任建立的时机。
                MoreAppsSection()

                AboutSection()
            }
            // 禁用设置页下拉弹性（内容不足一屏时完全拉不动）
            .disableBounce()
            // v1.3.4m：全部菜单条目图标统一红色（LabelStyle 传播到所有 section）
            .labelStyle(SettingsRedIconLabelStyle())
            // 统一页头规范（2026-10-15）：隐藏系统导航栏，保留 navigationTitle
            // 供 VoiceOver 与深链标题（与其他 8 页一致）
            .navigationTitle(L10n.shared.设置)
            .toolbar(.hidden, for: .navigationBar)
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
                                // 修复（2026-10-14）：iCloud 开启时重置会先清除云端副本，
                                // 失败则中止并保留本地数据。必须回显真实原因，不能笼统报「重置失败」。
                                viewModel.resetDatabase { result in
                                    switch result {
                                    case .success:
                                        resetAlert = .success
                                    case .failure(let error):
                                        // 判据（修复 2026-10-14 审查 P1-3）：按错误**类型**分流，
                                        // 不再靠「文案是否为空」猜。userMessage 对非云端错误返回空串，
                                        // 本地失败必须显示自己的真实原因，不能谎报成云端失败 +
                                        // 「本机数据未做任何改动」（对 store 重载失败这类场景两句话都是假的）。
                                        let cloudMessage = CloudKitPurgeService.userMessage(for: error)
                                        if cloudMessage.isEmpty {
                                            let reason = (error as? LocalizedError)?.errorDescription
                                                ?? L10n.shared.重置数据库失败提示
                                            resetAlert = .resetFailed(reason)
                                        } else {
                                            resetAlert = .cloudPurgeFailed(cloudMessage)
                                        }
                                    }
                                }
                            }
                        }
                    case .success:
                        Button(L10n.shared.好的, role: .cancel) {}
                    case .resetFailed:
                        Button(L10n.shared.好的, role: .cancel) {}
                    case .exportFailed:
                        Button(L10n.shared.好的, role: .cancel) {}
                    case .exportNoData:
                        Button(L10n.shared.好的, role: .cancel) {}
                    case .exportNotReady:
                        Button(L10n.shared.好的, role: .cancel) {}
                    case .restoreSuccess:
                        Button(L10n.shared.好的, role: .cancel) {}
                    case .restoreFailure:
                        Button(L10n.shared.好的, role: .cancel) {}
                    case .cloudPurgeFailed:
                        Button(L10n.shared.好的, role: .cancel) {}
                    }
                },
                message: { type in
                    switch type {
                    case .confirm:
                        // iCloud 开启时会连云端副本一起删除，文案必须明示，
                        // 否则用户在多设备上会误以为只清了本机
                        Text(viewModel.iCloudSyncEnabled
                             ? L10n.shared.重置数据库确认提示含云端
                             : L10n.shared.重置数据库确认提示)
                    case .success:
                        Text(L10n.shared.重置数据库成功提示)
                    case .resetFailed(let reason):
                        Text(reason)
                    case .exportFailed:
                        Text(L10n.shared.导出失败提示)
                    case .exportNoData:
                        Text(L10n.shared.无可导出数据提示)
                    case .exportNotReady:
                        Text(L10n.shared.数据未就绪提示)
                    case .restoreSuccess:
                        Text(L10n.shared.恢复成功提示)
                    case .restoreFailure:
                        Text(L10n.shared.恢复失败提示)
                    case .cloudPurgeFailed(let reason):
                        Text(reason + "\n\n" + L10n.shared.云端清除失败本地未改动)
                    }
                }
            )
            // 分享面板（导出/备份共用单一 sheet；`item:` 呈现，nil 即关闭）
            .sheet(item: $sharePayload) { payload in
                ShareSheet(items: payload.urls)
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
        .environmentObject(L10n.shared)
}

import SwiftUI
import StoreKit

// MARK: - PinDial 详情页
// v1.3.4：从「我的其他应用」菜单行进入。承载图标、卖点标签、一段简介与「功能亮点」
// 分点说明，底部「获取 PinDial」按钮在应用内弹出商店页（单层 present，避免双跳）。
struct PinDialDetailView: View {
    @EnvironmentObject var l10n: L10n
    @Environment(\.openURL) private var openURL
    @State private var showFallbackAlert = false
    // 持有 StorePresenter（引用类型），防止其被释放导致 store.delegate 失效、无法 dismiss
    @State private var presenter: StorePresenter?

    // PinDial App Store ID（来自 PinDial 工程 planning 文档与 iTunes lookup 核验）
    private static let pinDialAppID = 6773562304
    // 兜底链接（区域自适应，由系统跳转到用户所在区商店）
    private static let pinDialFallbackURL = URL(string: "https://apps.apple.com/app/id\(pinDialAppID)")!

    var body: some View {
        ScrollView {
            VStack(alignment: .center, spacing: 18) {
                // 应用图标
                Image("pindial-icon")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .accessibilityHidden(true)

                // 名称（h1 语义，供 VoiceOver 锚定标题）
                Text("PinDial")
                    .font(.title.bold())
                    .accessibilityHeading(.h1)

                // 卖点标签（用户指定文案）
                Text(l10n.pindial推荐简介)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)

                // 获取按钮（应用内商店页，失败则弹 Alert 询问，绝不自动跳转）
                Button {
                    openPinDialStore()
                } label: {
                    Text(l10n.pindial获取按钮)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(minWidth: 200)
                        .padding(.vertical, 10)
                        .background(Color(red: 0.0, green: 0.48, blue: 0.91))
                        .clipShape(Capsule())
                }
                .accessibilityHint(l10n.打开AppStore查看PinDial)
                .padding(.top, 4)

                Divider()
                    .padding(.vertical, 8)

                // 简介 + 功能亮点（左对齐、占满宽度）
                VStack(alignment: .leading, spacing: 18) {
                    Text(l10n.pindial简介段落)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineSpacing(5)

                    Text(l10n.pindial功能亮点)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    featureBlock(title: l10n.pindial功能T9标题, content: l10n.pindial功能T9内容)
                    featureBlock(title: l10n.pindial功能拨号盘标题, content: l10n.pindial功能拨号盘内容)
                    featureBlock(title: l10n.pindial功能小组件标题, content: l10n.pindial功能小组件内容)
                    featureBlock(title: l10n.pindial功能越狱标题, content: l10n.pindial功能越狱内容)
                    featureBlock(title: l10n.pindial功能隐私标题, content: l10n.pindial功能隐私内容)
                    featureBlock(title: l10n.pindial功能原生标题, content: l10n.pindial功能原生内容)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
        }
        // 子页规范（与 PrivacyPolicyView 一致）：恢复导航栏 + inline 标题
        .disableBounce()
        .navigationTitle(l10n.pindial详情页标题)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .alert(l10n.商店页加载失败标题, isPresented: $showFallbackAlert) {
            Button(l10n.前往AppStore) { openURL(Self.pinDialFallbackURL) }
            Button(l10n.取消, role: .cancel) {}
        } message: {
            Text(l10n.商店页加载失败消息)
        }
    }

    private func featureBlock(title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text(content)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(4)
        }
    }

    private func openPinDialStore() {
        // 防止重复点击叠加多个商店页
        guard presenter == nil else { return }
        presenter = StorePresenter(appID: Self.pinDialAppID) {
            // 加载失败：弹 Alert 询问用户是否改用系统浏览器（不自动跳转）
            $showFallbackAlert.wrappedValue = true
        }
        // store 关闭后释放 presenter，允许再次打开
        presenter?.onDidDismiss = { $presenter.wrappedValue = nil }
        presenter?.present()
    }
}

// MARK: - 应用内 App Store 产品页 Presenter
// 直接 present SKStoreProductViewController 到 keyWindow.rootViewController（单层模态），
// 规避 SwiftUI .sheet 包裹全屏 VC 导致的双层转场（双跳）。
final class StorePresenter: NSObject, SKStoreProductViewControllerDelegate {
    let store: SKStoreProductViewController
    let onLoadFailed: () -> Void
    var onDidDismiss: (() -> Void)?

    init(appID: Int, onLoadFailed: @escaping () -> Void) {
        self.store = SKStoreProductViewController()
        self.onLoadFailed = onLoadFailed
        super.init()
        store.delegate = self
        store.loadProduct(withParameters: [
            SKStoreProductParameterITunesItemIdentifier: NSNumber(value: appID)
        ]) { [weak self] success, _ in
            if !success {
                // 真机首次加载常先回调一次 false（随后自行重试成功），
                // 仅当确实失败时收起并询问用户，避免误触发双跳。
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.store.dismiss(animated: true) {
                        self.onLoadFailed()
                        self.onDidDismiss?()
                    }
                }
            }
        }
    }

    func present() {
        guard let root = StorePresenter.keyRootViewController() else {
            onLoadFailed()
            return
        }
        root.present(store, animated: true)
    }

    func productViewControllerDidFinish(_ controller: SKStoreProductViewController) {
        controller.dismiss(animated: true) { [weak self] in
            self?.onDidDismiss?()
        }
    }

    private static func keyRootViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .first { $0.activationState == .foregroundActive } as? UIWindowScene
        return scene?.windows.first { $0.isKeyWindow }?.rootViewController
    }
}

#Preview {
    NavigationStack {
        PinDialDetailView()
            .environmentObject(L10n.shared)
    }
}

import SwiftUI

struct AboutSection: View {
    @EnvironmentObject var l10n: L10n
    // v1.3.4p：openURL 打开 App Store 评分页（iOS 14+）
    @Environment(\.openURL) private var openURL

    // App ID 6778738267（FlowTakt 流刻）；?action=write-review 直达评分撰写
    private static let appStoreReviewURL = URL(string: "https://apps.apple.com/app/id6778738267?action=write-review")!

    var body: some View {
        Section {
            NavigationLink {
                UsageGuideView()
            } label: {
                Label(L10n.shared.使用说明, systemImage: "book.pages.fill")
            }

            NavigationLink {
                PrivacyPolicyView()
            } label: {
                Label(L10n.shared.隐私政策, systemImage: "hand.raised.fill")
            }

            // 应用名称 + 版本号（v1.3.4p 优化：合并到一行，替代独立「版本」行）
            // 无障碍（2026-08-17）：整行合并为一个朗读元素（"应用名称, FlowTakt 1.3.1"），icon 由 SettingsRedIconLabelStyle 统一隐藏
            HStack {
                Label(L10n.shared.应用名称, systemImage: "app.fill")
                Spacer()
                Text(appNameWithVersion)
                    .foregroundColor(.secondary)
            }
            .accessibilityElement(children: .combine)

            // v1.3.4p：在 App Store 评分（置于 section 最底；用户主动触发，避免强迫）
            // 无障碍（2026-08-17）：Label icon 隐藏（避免读 SF Symbol 名），补 hint 说明跳转行为
            Button {
                openURL(Self.appStoreReviewURL)
            } label: {
                Label {
                    Text(L10n.shared.在AppStore评分)
                } icon: {
                    Image(systemName: "star.fill")
                        .accessibilityHidden(true)
                }
            }
            .accessibilityHint(L10n.shared.打开AppStore评分)
        } header: {
            Text(L10n.shared.关于)
        }
    }

    /// 应用名称 + 版本号（v1.3.4p：合并显示，替代独立的「版本」行）
    private var appNameWithVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "FlowTakt \(version)"
    }
}

#Preview {
    Form {
        AboutSection()
    }
}

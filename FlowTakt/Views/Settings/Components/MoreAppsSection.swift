import SwiftUI

// MARK: - 我的其他应用（PinDial 入口）
// v1.3.4：设置页「关于」上方的开发者其他应用入口。
// 形态为与「使用说明 / 隐私政策」一致的标准菜单行：左侧 PinDial 应用图标 + 名称，
// 右侧系统箭头；点击进入 PinDialDetailView 查看详细介绍与下载入口。
struct MoreAppsSection: View {
    @EnvironmentObject var l10n: L10n

    var body: some View {
        Section {
            NavigationLink {
                PinDialDetailView()
            } label: {
                HStack(spacing: 14) {
                    Image("pindial-icon")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 30, height: 30)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .accessibilityHidden(true)
                    Text("PinDial")
                    Spacer(minLength: 4)
                }
            }
            // 整行合并为单一无障碍元素：「名称 + 我的其他应用」
            .accessibilityElement(children: .combine)
            .accessibilityLabel("PinDial, \(l10n.我的其他应用)")
        } header: {
            Text(l10n.我的其他应用)
        }
    }
}

#Preview {
    Form {
        MoreAppsSection()
    }
    .environmentObject(L10n.shared)
}

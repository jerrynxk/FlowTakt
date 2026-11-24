import SwiftUI

// MARK: - 隐私政策视图

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var l10n: L10n

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 在线版链接（审核与用户可访问的托管页面，C1）
                if let url = URL(string: AppConstants.privacyPolicyURL) {
                    Link(destination: url) {
                        Label(L10n.shared.在线查看隐私政策, systemImage: "safari")
                            .font(.subheadline)
                            .foregroundColor(.focusRed)
                    }
                    .padding(.bottom, 4)
                }

                // 最后更新日期
                Text(L10n.shared.最后更新日期)
                    .font(.caption)
                    .foregroundColor(.secondary)

                // 引言
                Text(L10n.shared.隐私引言)
                    .font(.body)
                    .foregroundColor(.primary)

                // 信息收集
                policySection(
                    title: L10n.shared.信息收集标题,
                    content: L10n.shared.信息收集内容
                )

                // 信息使用
                policySection(
                    title: L10n.shared.信息使用标题,
                    content: L10n.shared.信息使用内容
                )

                // 数据存储
                policySection(
                    title: L10n.shared.数据存储标题,
                    content: L10n.shared.数据存储内容
                )

                // iCloud同步
                policySection(
                    title: L10n.shared.iCloud同步标题,
                    content: L10n.shared.iCloud同步内容
                )

                // 通知权限
                policySection(
                    title: L10n.shared.通知权限标题,
                    content: L10n.shared.通知权限内容
                )

                // 第三方服务
                policySection(
                    title: L10n.shared.第三方服务标题,
                    content: L10n.shared.第三方服务内容
                )

                // 用户权利
                policySection(
                    title: L10n.shared.用户权利标题,
                    content: L10n.shared.用户权利内容
                )

                // 儿童隐私
                policySection(
                    title: L10n.shared.儿童隐私标题,
                    content: L10n.shared.儿童隐私内容
                )

                // 政策变更
                policySection(
                    title: L10n.shared.政策变更标题,
                    content: L10n.shared.政策变更内容
                )

                // 联系我们
                policySection(
                    title: L10n.shared.联系我们标题,
                    content: L10n.shared.联系我们内容
                )
            }
            .padding()
        }
        .disableBounce()
        .navigationTitle(L10n.shared.隐私政策)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        // 修复（2026-10-15 审查）：父级 SettingsView 统一页头规范后隐藏导航栏，
        // pushed 子页必须显式恢复，否则「确定」按钮所在工具栏不可见
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(L10n.shared.确定) {
                    dismiss()
                }
            }
        }
    }

    private func policySection(title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
                // 无障碍补齐（2026-11-02）：11 个章节标题补二级标题语义 ——
                // 长文档此前无法通过「转子 → 标题」快速跳转到某一节
                .accessibilityHeading(.h2)
            Text(content)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineSpacing(4)
        }
    }
}

#Preview {
    NavigationStack {
        PrivacyPolicyView()
            .environmentObject(L10n.shared)
    }
}

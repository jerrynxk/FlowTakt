import SwiftUI

// MARK: - 使用说明视图

struct UsageGuideView: View {
    @EnvironmentObject var l10n: L10n
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.shared.usageGuideOverview)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section {
                GuideRow(icon: "clock.arrow.circlepath", color: .red, title: L10n.shared.focus, content: L10n.shared.guideContent(for: "focus"))
            } header: {
                Text(L10n.shared.模块说明)
            }

            Section {
                GuideRow(icon: "list.bullet", color: .blue, title: L10n.shared.任务, content: L10n.shared.guideContent(for: "task"))
            }

            Section {
                GuideRow(icon: "calendar", color: .orange, title: L10n.shared.日程, content: L10n.shared.guideContent(for: "calendar"))
            }

            Section {
                GuideRow(icon: "checkmark.circle.fill", color: .green, title: L10n.shared.习惯, content: L10n.shared.guideContent(for: "habit"))
            }

            Section {
                GuideRow(icon: "stopwatch.fill", color: .purple, title: L10n.shared.计时, content: L10n.shared.guideContent(for: "timer"))
            }

            Section {
                GuideRow(icon: "chart.bar.fill", color: .teal, title: L10n.shared.stats, content: L10n.shared.guideContent(for: "stats"))
            }

            Section {
                GuideRow(icon: "trophy.fill", color: .yellow, title: L10n.shared.成就, content: L10n.shared.guideContent(for: "achievement"))
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.shared.番茄工作法小贴士)
                        .font(.headline)
                    Text(L10n.shared.pomodoroTips.joined(separator: "\n"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            } header: {
                Text(L10n.shared.效率建议)
            }
        }
        .navigationTitle(L10n.shared.使用说明)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(L10n.shared.确定) {
                    dismiss()
                }
            }
        }
    }
}

// MARK: - 说明行组件

private struct GuideRow: View {
    let icon: String
    let color: Color
    let title: String
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.title3)
                Text(title)
                    .font(.headline)
            }

            Text(content)
                .font(.subheadline)
                .foregroundColor(.primary.opacity(0.7))
                .lineSpacing(4)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        UsageGuideView()
    }
}

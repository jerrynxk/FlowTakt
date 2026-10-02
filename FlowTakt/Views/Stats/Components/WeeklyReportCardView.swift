import SwiftUI

// MARK: - 周报分享卡片（B3）
// 供 ImageRenderer 渲染为图片分享；卡片为浅色设计，适配聊天/社交分享。

struct WeeklyReportCardView: View {
    let weekLabel: String
    let completedPomodoros: Int
    let totalMinutes: Int
    let streak: Int
    let totalCompleted: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 品牌区
            HStack(spacing: 8) {
                Image(systemName: "timer.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.focusRed)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.shared.应用名称)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    Text(L10n.shared.专注周报)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text(weekLabel)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 24)

            // 本周番茄大数字
            VStack(spacing: 6) {
                Text("\(completedPomodoros)")
                    .font(.system(size: 72, weight: .heavy, design: .rounded))
                    .foregroundColor(.focusRed)
                Text(L10n.shared.本周完成番茄)
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(Color.focusRed.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.bottom, 20)

            // 数据行
            HStack(spacing: 12) {
                statBlock(icon: "clock.fill", color: .blue,
                          value: L10n.shared.分钟(totalMinutes),
                          label: L10n.shared.专注时长周报)
                statBlock(icon: "flame.fill", color: .orange,
                          value: "\(streak)",
                          label: L10n.shared.连续天数)
                statBlock(icon: "checkmark.circle.fill", color: .green,
                          value: "\(totalCompleted)",
                          label: L10n.shared.累计完成)
            }

            Spacer(minLength: 16)

            // 口号
            Text(L10n.shared.专注周报口号)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
        )
    }

    private func statBlock(icon: String, color: Color, value: String, label: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(color)
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

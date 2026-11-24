import SwiftUI

// MARK: - 总专注时长汇总卡（用户反馈 2026-11-19）
//
// 背景：番茄时长支持自定义，"完成几个番茄"无法反映真实投入。
// 本卡只呈现与番茄时长无关的指标 —— 净专注时长（番茄 completed/earlyCompleted + 正计时），
// 分 今日 / 本周 / 本月 / 累计 四档，口径与「今日专注」完全一致（判据在 StatsViewModel 内收口）。

struct DurationSummaryCard: View {
    @EnvironmentObject var statsViewModel: StatsViewModel
    @EnvironmentObject var l10n: L10n

    private struct Item: Identifiable {
        let id: String
        let label: String
        let seconds: TimeInterval
    }

    private var items: [Item] {
        [
            Item(id: "today", label: L10n.shared.今日, seconds: statsViewModel.todayDuration),
            Item(id: "week", label: L10n.shared.本周, seconds: statsViewModel.weekDuration),
            Item(id: "month", label: L10n.shared.本月, seconds: statsViewModel.monthDuration),
            Item(id: "total", label: L10n.shared.累计, seconds: statsViewModel.totalDuration)
        ]
    }

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "clock.fill")
                    .foregroundColor(.focusRed)
                    // 无障碍：装饰图标不单独朗读
                    .accessibilityHidden(true)
                Text(L10n.shared.总专注时长)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .accessibilityHeading(.h2)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.label)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        // 等宽数字 + 缩放兜底：大字号下"X小时X分钟"可能较长，不换行而是缩小
                        Text(item.seconds.formattedDuration)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(item.seconds > 0 ? .primary : .secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.cardInsetFill)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    // 无障碍：合并为「今日 1小时20分钟」
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(item.label) \(item.seconds.formattedDuration)")
                }
            }
            .padding(16)
        }
        .cardStyle()
    }
}

#if DEBUG
struct DurationSummaryCard_Previews: PreviewProvider {
    static var previews: some View {
        DurationSummaryCard()
            .environmentObject(StatsViewModel(
                focusService: FocusService(
                    persistenceController: PersistenceController.shared,
                    notificationService: NotificationService()
                ),
                taskService: TaskService(persistenceController: PersistenceController.shared),
                persistenceController: PersistenceController.shared
            ))
            .padding()
            .background(Color.appBackground)
            .environmentObject(L10n.shared)
    }
}
#endif

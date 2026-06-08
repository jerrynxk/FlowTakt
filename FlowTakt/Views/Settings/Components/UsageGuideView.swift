import SwiftUI

// MARK: - 使用说明视图

struct UsageGuideView: View {
    var body: some View {
        List {
            // 概览
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("FlowTakt 是一站式效率工具，融合番茄钟专注、任务管理、习惯追踪与时间统计，帮你掌控每一天的节奏。")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }

            // 专注
            Section {
                GuideRow(
                    icon: "clock.arrow.circlepath",
                    color: .red,
                    title: "专注",
                    content: """
                    番茄工作法的核心模块。
                    · 点击「开始」进入 25 分钟专注（可在设置中调整时长）。
                    · 每完成一个番茄钟自动进入短休息，累计 4 轮进入长休息。
                    · 可将当前专注绑定到具体任务，专注结束后自动计入任务进度。
                    · 专注期间会播放白噪音并屏蔽通知，帮助保持心流状态。
                    """
                )
            } header: {
                Text("模块说明")
            }

            // 任务
            Section {
                GuideRow(
                    icon: "list.bullet",
                    color: .blue,
                    title: "任务",
                    content: """
                    管理待办事项，按优先级排序。
                    · 创建任务时可估算所需番茄钟数量。
                    · 任务完成后自动归档，支持查看历史记录。
                    · 支持按状态（活跃/已完成/归档）筛选。
                    · 长按任务可拖拽排序，左滑可快速完成或删除。
                    """
                )
            }

            // 日历
            Section {
                GuideRow(
                    icon: "calendar",
                    color: .orange,
                    title: "日历",
                    content: """
                    日程安排与时间块规划。
                    · 创建日程项设置标题、时间和地点。
                    · 支持全天事件和跨天安排。
                    · 可将日程关联到具体任务，实现任务与时间的联动。
                    · 日历视图按日/周/月切换查看。
                    """
                )
            }

            // 习惯
            Section {
                GuideRow(
                    icon: "checkmark.circle.fill",
                    color: .green,
                    title: "习惯",
                    content: """
                    培养并追踪每日习惯。
                    · 创建习惯设置名称、频率（每日/每周）和目标次数。
                    · 每天打卡记录完成情况，直观看到连续坚持天数。
                    · 连续天数（Streak）和最长连续记录激励持续进步。
                    · 支持自定义图标和颜色，个性化每个习惯。
                    """
                )
            }

            // 计时
            Section {
                GuideRow(
                    icon: "stopwatch.fill",
                    color: .purple,
                    title: "计时",
                    content: """
                    自由计时器，适用于非番茄钟场景。
                    · 开始计时后记录实际工作时长，可关联任务和标签。
                    · 支持标记是否可计费（适合自由职业者）。
                    · 完成后自动生成时间记录，可在统计中查看汇总。
                    · 适合会议、深度工作等灵活时长场景。
                    """
                )
            }

            // 统计
            Section {
                GuideRow(
                    icon: "chart.bar.fill",
                    color: .teal,
                    title: "统计",
                    content: """
                    数据可视化，洞察你的效率趋势。
                    · 今日概览：当日专注时长、完成任务数、连续天数。
                    · 周度图表：一周内每日专注时长柱状图。
                    · 任务分布：按标签/项目分类的时间投入饼图。
                    · 洞察卡片：基于历史数据给出的效率建议。
                    """
                )
            }

            // 成就
            Section {
                GuideRow(
                    icon: "trophy.fill",
                    color: .yellow,
                    title: "成就",
                    content: """
                    游戏化激励，让专注更有趣。
                    · 完成里程碑自动解锁对应成就徽章。
                    · 成就分为：累积型（总数达标）、连续型（连续坚持）、特殊成就。
                    · 每次解锁伴随动画特效和积分奖励。
                    · 积分可用于未来版本的道具/主题兑换。
                    """
                )
            }

            // 番茄工作法小贴士
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("番茄工作法小贴士")
                        .font(.headline)
                    Text("""
                    ① 一次只做一件事，专注期间关闭所有干扰。
                    ② 每个番茄钟结束后务必休息，哪怕只是站起来走走。
                    ③ 如果被打断，记录中断原因，并重新开始当前番茄钟。
                    ④ 不要连续超过 8 个番茄钟，避免认知疲劳。
                    ⑤ 每天回顾统计页面，了解自己的高效时段。
                    """)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            } header: {
                Text("效率建议")
            }
        }
        .navigationTitle("使用说明")
        .navigationBarTitleDisplayMode(.inline)
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
                .foregroundColor(.secondary)
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

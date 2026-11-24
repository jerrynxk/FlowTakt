import WidgetKit
import SwiftUI

// MARK: - 入口

@main
struct FlowTaktWidgetBundle: WidgetBundle {
    var body: some Widget {
        ReminderWidget()
        // 专注 Live Activity（灵动岛 + 锁屏，2026-10-14）。
        // 部署目标 16.0 < ActivityKit 完整能力的 16.2，故做可用性判断：
        // 16.2 以下系统不注册该 Widget（仅影响灵动岛/锁屏活动展示）。
        if #available(iOSApplicationExtension 16.2, *) {
            FocusLiveActivityWidget()
        }
    }
}

// MARK: - 小组件定义

struct ReminderWidget: Widget {
    let kind = "ReminderWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ReminderProvider()) { entry in
            ReminderWidgetView(entry: entry)
                // 点击小组件深链：打开 App 并跳转到「计划 → 日程」
                .widgetURL(URL(string: "flowtakt://schedule"))
                // 注：背景已改用 iOS 17 强制的 containerBackground（见 ReminderWidgetView），
                // 此前的 .background(Color(.secondarySystemBackground)) 属旧 API，
                // 在真机（锁屏 / 待机 / 部分主屏环境）会显示
                // "Please adopt containerBackground API" 占位提示（2026-10-15 修复）。
        }
        .configurationDisplayName(displayName)
        .description(descriptionText)
        .supportedFamilies([.systemSmall, .systemMedium,
                            .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }

    private var displayName: String {
        isEnglish ? "FlowTakt Reminders" : "FlowTakt 提醒"
    }

    private var descriptionText: String {
        isEnglish
        ? "Upcoming birthdays, anniversaries and client visits."
        : "临近的生日、纪念日与客户拜访。"
    }

    private var isEnglish: Bool {
        Self.widgetIsEnglish
    }

    /// 语言偏好：复用共享 WidgetLanguage（App Group 优先，无记录回退系统语言）
    static var widgetIsEnglish: Bool {
        WidgetLanguage.isEnglish
    }
}

// MARK: - 时间线

struct ReminderProvider: TimelineProvider {
    func placeholder(in context: Context) -> ReminderEntry {
        ReminderEntry(date: Date(), snapshot: Self.sampleSnapshot())
    }

    func getSnapshot(in context: Context, completion: @escaping (ReminderEntry) -> Void) {
        if context.isPreview {
            completion(ReminderEntry(date: Date(), snapshot: Self.sampleSnapshot()))
        } else {
            completion(ReminderEntry(date: Date(), snapshot: WidgetDataStore.read()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ReminderEntry>) -> Void) {
        let snapshot = WidgetDataStore.read()
        let entry = ReminderEntry(date: Date(), snapshot: snapshot)
        // 跨天后自动刷新；数据变更时由 App 调用 WidgetCenter.reloadAllTimelines() 主动刷新
        // 用 calendar.date(byAdding: .day) 计算次日，避免 DST 切换日 86400s 偏差
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let nextMidnight = (calendar.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart)
            .addingTimeInterval(5)
        let timeline = Timeline(entries: [entry], policy: .after(nextMidnight))
        completion(timeline)
    }

    private static func sampleSnapshot() -> WidgetSnapshot {
        let now = Date()
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        let nextWeek = calendar.date(byAdding: .day, value: 7, to: now)!
        return WidgetSnapshot(reminders: [
            WidgetReminder(id: "sample1", title: "妈妈生日", categoryRaw: "birthday", colorHex: "#FF3B30", nextDate: tomorrow, isAllDay: true),
            WidgetReminder(id: "sample2", title: "结婚纪念日", categoryRaw: "anniversary", colorHex: "#AF52DE", nextDate: nextWeek, isAllDay: true),
            WidgetReminder(id: "sample3", title: "拜访张总", categoryRaw: "visit", colorHex: "#007AFF", nextDate: tomorrow, isAllDay: false)
        ], updatedAt: now)
    }
}

struct ReminderEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

// MARK: - 视图

struct ReminderWidgetView: View {

    var entry: ReminderEntry
    @Environment(\.widgetFamily) private var family

    private var isEnglish: Bool {
        ReminderWidget.widgetIsEnglish
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryRectangular, .accessoryInline:
                AccessoryReminderView(entry: entry, family: family)
            case .accessoryCircular:
                AccessoryCircularView(entry: entry)
            default:
                standardContent
            }
        }
        // iOS 17+ 强制要求采用 containerBackground：未采用的 widget 在真机
        // （锁屏 / StandBy / 部分主屏渲染环境）会显示
        // "Please adopt containerBackground API" 占位提示（2026-10-15 修复）。
        // 主屏幕沿用原 secondarySystemBackground；锁屏 accessory 系列背景交还系统
        // （clear，由系统绘制 vibrancy 材质，自定义色会被忽略且可能干扰）。
        .containerBackground(for: .widget) {
            switch family {
            case .systemSmall, .systemMedium:
                Color(.secondarySystemBackground)
            default:
                Color.clear
            }
        }
    }

    @ViewBuilder
    private var standardContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "bell.badge.fill")
                    .font(.caption)
                    .foregroundColor(.accentColor)
                Text(isEnglish ? "Upcoming" : "临近提醒")
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer(minLength: 0)
            }

            if let reminders = entry.snapshot?.reminders, !reminders.isEmpty {
                ForEach(reminders.prefix(4)) { reminder in
                    // 逐条深链：点击具体提醒跳转到对应日程事件
                    // 崩溃修复（2026-10-02）：reminder.id 来自 App Group 持久化数据，
                    // URL(string:) 对含非法字符的字符串返回 nil，强解包会 EXC_BAD_ACCESS
                    // （且崩在 Widget 扩展进程）。URL 构造失败时降级为不可点的纯文本。
                    if let url = URL(string: "flowtakt://schedule/\(reminder.id)") {
                        Link(destination: url) {
                            ReminderRow(reminder: reminder)
                        }
                    } else {
                        ReminderRow(reminder: reminder)
                    }
                }
                if reminders.count > 4 {
                    Spacer(minLength: 0)
                }
            } else {
                Spacer(minLength: 0)
                Text(isEnglish ? "No upcoming reminders" : "暂无临近提醒")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer(minLength: 0)
            }
        }
        .padding(12)
    }
}

// MARK: - 锁屏 / 灵动岛 紧凑视图（accessory 系列）

/// 矩形 / 单行：今日专注摘要 + 下一条临近提醒（逐条深链）
private struct AccessoryReminderView: View {
    let entry: ReminderEntry
    let family: WidgetFamily
    private let calendar = Calendar.current
    private var isEnglish: Bool { ReminderWidget.widgetIsEnglish }

    var body: some View {
        let summary = WidgetDataStore.readFocusSummary()
        let reminders = entry.snapshot?.reminders ?? []

        if family == .accessoryInline {
            Text(inlineText(summary: summary, reminders: reminders))
                .widgetURL(URL(string: "flowtakt://schedule"))
        } else {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Image(systemName: "timer")
                        .imageScale(.small)
                    Text(focusText(summary: summary))
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                }
                if let next = reminders.first {
                    // 崩溃修复（2026-10-02）：同上，URL 构造失败时降级为不可点的纯文本
                    let row = nextReminderLabel(next: next)
                    if let url = URL(string: "flowtakt://schedule/\(next.id)") {
                        Link(destination: url) { row }
                    } else {
                        row
                    }
                } else {
                    Text(isEnglish ? "No reminders" : "暂无提醒")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .widgetURL(URL(string: "flowtakt://schedule"))
        }
    }

    /// 「下一条提醒」行（崩溃修复 2026-10-02：抽为独立 View 以便深链与降级纯文本复用）
    private func nextReminderLabel(next: WidgetReminder) -> some View {
        HStack(spacing: 4) {
            Image(systemName: ScheduleCategory(rawValue: next.categoryRaw)?.iconName ?? "bell")
                .imageScale(.small)
            Text(next.title)
                .font(.subheadline)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(countdownText(for: next))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func focusText(summary: WidgetDataStore.FocusSummary?) -> String {
        if let s = summary {
            return isEnglish
                ? "\(s.completedPomodoros) · \(s.totalMinutes)m"
                : "\(s.completedPomodoros) 个 · \(s.totalMinutes) 分"
        }
        return isEnglish ? "No focus" : "未专注"
    }

    private func inlineText(summary: WidgetDataStore.FocusSummary?, reminders: [WidgetReminder]) -> String {
        let f = focusText(summary: summary)
        if let next = reminders.first {
            return "\(f) · \(next.title)"
        }
        return f
    }

    private func countdownText(for reminder: WidgetReminder) -> String {
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: Date()),
            to: calendar.startOfDay(for: reminder.nextDate)
        ).day ?? 0
        if days <= 0 { return isEnglish ? "Today" : "今天" }
        if days == 1 { return isEnglish ? "Tomorrow" : "明天" }
        return isEnglish ? "\(days)d" : "\(days)天"
    }
}

/// 圆形：今日完成番茄数
private struct AccessoryCircularView: View {
    /// 进度弧上限（与「每日 8 个番茄」量级一致）；修复 P2：原先上界=值本身 → 弧恒满格
    static let gaugeCeiling = 8

    let entry: ReminderEntry
    private var isEnglish: Bool { ReminderWidget.widgetIsEnglish }

    var body: some View {
        let summary = WidgetDataStore.readFocusSummary()
        let count = summary?.completedPomodoros ?? 0
        // 修复（P2）：原区间上界 = 值本身 → 进度弧恒为满格，不携带信息。改为固定上限。
        Gauge(value: Double(min(count, AccessoryCircularView.gaugeCeiling)), in: 0...Double(AccessoryCircularView.gaugeCeiling)) {
            Image(systemName: "timer")
                // 无障碍补齐（2026-11-02）：Gauge 的 label 只承载图标时，
                // 读屏会把它念成「计时器」而非「今日完成番茄」
                .accessibilityHidden(true)
        } currentValueLabel: {
            Text("\(count)").font(.headline)
        }
        .gaugeStyle(.accessoryCircular)
        .accessibilityLabel(isEnglish ? "Pomodoros completed today" : "今日完成番茄")
        .widgetURL(URL(string: "flowtakt://focus"))
    }
}

private struct ReminderRow: View {
    let reminder: WidgetReminder
    private let calendar = Calendar.current

    private var isEnglish: Bool {
        ReminderWidget.widgetIsEnglish
    }

    var body: some View {
        let cat = ScheduleCategory(rawValue: reminder.categoryRaw) ?? .event
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: Date()),
            to: calendar.startOfDay(for: reminder.nextDate)
        ).day ?? 0

        let countdownText: String = {
            if days <= 0 { return isEnglish ? "Today" : "今天" }
            if days == 1 { return isEnglish ? "Tomorrow" : "明天" }
            return isEnglish ? "in \(days) days" : "还有 \(days) 天"
        }()

        HStack(spacing: 8) {
            Image(systemName: cat.iconName)
                .foregroundColor(Color(hex: reminder.colorHex ?? "#007AFF"))
                .font(.caption)
                .frame(width: 16)
                // 无障碍补齐（2026-11-02）：分类图标不单独朗读（分类名已在下方文案中）
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text("\(cat.displayName) · \(countdownText)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        // 无障碍补齐（2026-11-02）：标题、分类、倒计时原被拆成 3 个碎片元素，
        // 合并为一句「妈妈生日，生日，明天」
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            [reminder.title, cat.displayName, countdownText]
                .joined(separator: isEnglish ? ", " : "，")
        )
    }
}

// MARK: - 颜色辅助（与 App 端 Color(hex:) 对齐，Widget 独立实现）

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (r, g, b) = (int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1
        )
    }
}

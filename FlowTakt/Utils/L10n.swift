import Foundation
import SwiftUI
import Combine

// MARK: - 运行时英文本地化（ObservableObject 单例，支持 SwiftUI 响应式刷新）

final class L10n: ObservableObject {
    static let shared = L10n()

    @Published var appLanguage: String = {
        if let stored = UserDefaults.standard.string(forKey: "appLanguage"), !stored.isEmpty {
            return stored
        }
        // 首次启动：跟随系统语言（英文系统默认英文，其余默认中文），避免英文系统首启即中文
        let preferred = Locale.preferredLanguages.first ?? "zh-Hans"
        return preferred.hasPrefix("en") ? "en" : "zh-Hans"
    }() {
        didSet {
            // 注意：@Published 的 willSet 已自动发送 objectWillChange，此处不再重复发送
            UserDefaults.standard.set(appLanguage, forKey: "appLanguage")
            // 同步到 App Group，保证 Widget 端语言与主 App 一致
            WidgetDataStore.writeLanguage(appLanguage)
        }
    }

    var isEnglish: Bool {
        appLanguage.hasPrefix("en")
    }

    /// 静态访问入口，供所有 static 方法使用
    static var isEnglish: Bool {
        shared.appLanguage.hasPrefix("en")
    }

    // MARK: - 插值字符串（函数）

    func round(_ index: Int) -> String {
        isEnglish ? "Round \(index)" : "第 \(index) 轮"
    }

    func todayCompleted(_ count: Int) -> String {
        isEnglish ? "Today completed \(count) pomodoros" : "今天已完成 \(count) 个番茄钟"
    }

    func longestStreak(_ days: Int) -> String {
        isEnglish ? "Longest streak: \(days) days" : "最长连续专注 \(days) 天"
    }

    func totalCompleted(_ count: Int) -> String {
        isEnglish ? "Total completed: \(count) pomodoros" : "累计完成 \(count) 个番茄钟"
    }

    /// 今日中断洞察（含最近一次中断原因）
    func todayInterrupted(_ count: Int, lastReason: String?) -> String {
        if let lastReason, !lastReason.isEmpty {
            return isEnglish ? "Interrupted \(count) time(s) today · \(lastReason)"
                             : "今日中断 \(count) 次 · \(lastReason)"
        }
        return isEnglish ? "Interrupted \(count) time(s) today" : "今日中断 \(count) 次"
    }

    func todayPoints(_ pts: Int) -> String {
        isEnglish ? "+\(pts) Points" : "+\(pts) 积分"
    }

    func estimatedPomodoros(_ count: Int) -> String {
        isEnglish ? "\(count) pomodoros" : "\(count) 个番茄钟"
    }

    func habitToday(_ count: Int, target: Int16) -> String {
        isEnglish ? "Today \(count)/\(target)" : "今日 \(count)/\(target)"
    }

    /// 周图柱状无障碍文案：某日完成 X 个番茄钟
    func dayPomodoros(_ day: String, count: Int) -> String {
        isEnglish ? "\(day): \(count) pomodoros" : "\(day)：\(count) 个番茄钟"
    }

    /// 日历单元格无障碍文案：某日 N 个日程
    func dayEventCount(_ count: Int) -> String {
        isEnglish ? "\(count) events" : "\(count)个日程"
    }

    // MARK: - 日程视图切换（A4）
    var 月视图: String { isEnglish ? "Month" : "月视图" }
    var 周视图: String { isEnglish ? "Week" : "周视图" }
    var 上一周: String { isEnglish ? "Previous Week" : "上一周" }
    var 下一周: String { isEnglish ? "Next Week" : "下一周" }

    // MARK: - 自然语言快速建日程（B2）
    var 快速添加日程: String { isEnglish ? "Quick Add" : "快速添加" }
    var 快速添加提示: String { isEnglish ? "e.g. 明天下午3点 开会 / 8月15日 体检" : "如：明天下午3点 开会 / 8月15日 体检" }

    // MARK: - 年热力图（A5）
    var 专注年热力图: String { isEnglish ? "Yearly Heatmap" : "专注年热力图" }
    func 年打卡天数(_ days: Int) -> String {
        isEnglish ? "\(days) active day(s) this year" : "今年打卡 \(days) 天"
    }
    var 少: String { isEnglish ? "Less" : "少" }
    var 多: String { isEnglish ? "More" : "多" }

    // MARK: - 周报分享卡片（B3）
    var 专注周报: String { isEnglish ? "Focus Report" : "专注周报" }
    var 分享周报: String { isEnglish ? "Share Report" : "分享周报" }
    var 本周完成番茄: String { isEnglish ? "Pomodoros This Week" : "本周完成番茄" }
    var 专注时长周报: String { isEnglish ? "Focus Time" : "专注时长" }
    var 连续天数: String { isEnglish ? "Day Streak" : "连续天数" }
    var 累计完成: String { isEnglish ? "Total" : "累计完成" }
    var 专注周报口号: String { isEnglish ? "Every pomodoro counts. Keep it up!" : "每一颗番茄都算数，继续坚持！" }

    // MARK: - 数据备份/恢复（B4）
    var 数据备份: String { isEnglish ? "Data Backup" : "数据备份" }
    var 备份数据: String { isEnglish ? "Back Up Data" : "备份数据" }
    var 恢复数据: String { isEnglish ? "Restore from Backup" : "恢复数据" }
    var 恢复成功提示: String { isEnglish ? "Data restored successfully." : "数据恢复成功。" }
    var 恢复失败提示: String { isEnglish ? "Restore failed. The file may be corrupted or incompatible." : "恢复失败，文件可能已损坏或不兼容。" }
    var 恢复确认提示: String { isEnglish ? "Restoring will REPLACE all current data. Continue?" : "恢复将覆盖当前全部数据，确定继续吗？" }

    // MARK: - 在线政策（C1）
    var 在线查看隐私政策: String { isEnglish ? "View Online" : "在线查看隐私政策" }

    func targetCount(_ count: Int) -> String {
        isEnglish ? "\(count) times" : "\(count) 次"
    }

    func deleteConfirm(_ title: String) -> String {
        isEnglish ? "Are you sure you want to delete \"\(title)\"? This cannot be undone." : "确定要删除「\(title)」吗？此操作不可撤销。"
    }

    var unlocked: String { isEnglish ? "Unlocked" : "已解锁" }
    var locked: String { isEnglish ? "Locked" : "未解锁" }

    // MARK: - 成就本地化

    func achievementTitle(_ identifier: String) -> String {
        switch identifier {
        case "first_pomodoro": return isEnglish ? "First Pomodoro" : "初次专注"
        case "pomodoros_10":   return isEnglish ? "Focus Beginner" : "专注新手"
        case "pomodoros_50":   return isEnglish ? "Focus Pro" : "专注达人"
        case "pomodoros_100":  return isEnglish ? "Focus Master" : "专注大师"
        case "streak_3":       return isEnglish ? "First Streak" : "初现坚持"
        case "streak_7":       return isEnglish ? "Weekly Streak" : "一周坚持"
        case "streak_30":      return isEnglish ? "Monthly Streak" : "月度坚持"
        case "points_100":     return isEnglish ? "Points Star" : "积分新星"
        case "points_500":     return isEnglish ? "Points Pro" : "积分达人"
        case "points_1000":    return isEnglish ? "Points Master" : "积分大师"
        default: return identifier
        }
    }

    func achievementDesc(_ identifier: String, threshold: Int) -> String {
        let count = threshold
        switch identifier {
        case "first_pomodoro": return isEnglish ? "Complete your first pomodoro" : "完成你的第一个番茄钟"
        case _ where identifier.hasPrefix("pomodoros_"):
            return isEnglish ? "Complete \(count) total pomodoros" : "累计完成 \(count) 个番茄钟"
        case _ where identifier.hasPrefix("streak_"):
            return isEnglish ? "Use Pomodoro for \(count) consecutive days" : "连续 \(count) 天使用番茄钟"
        case _ where identifier.hasPrefix("points_"):
            return isEnglish ? "Earn \(count) total points" : "累计获得 \(count) 积分"
        default: return identifier
        }
    }

    func achievementCategory(_ rawValue: String) -> String {
        switch rawValue {
        case "total":    return isEnglish ? "Cumulative" : "累积成就"
        case "streak":   return isEnglish ? "Streak" : "连续成就"
        case "special":  return isEnglish ? "Special" : "特殊成就"
        case "speed":    return isEnglish ? "Speed" : "速度成就"
        default: return rawValue
        }
    }

    var totalPoints: String { isEnglish ? "Total Points" : "总积分" }
    var todayPointsText: String { isEnglish ? "Today's Points" : "今日积分" }
    var 今日积分: String { todayPointsText }
    var 今日完成: String { isEnglish ? "Completed Today" : "今日完成" }

    // MARK: - 空状态

    var noTasks: String { isEnglish ? "No tasks yet" : "还没有任务" }
    var 创建第一个任务: String { isEnglish ? "Create your first task" : "创建第一个任务" }
    var createFirstTask: String { isEnglish ? "Create your first task to start managing time efficiently" : "点击下方按钮创建你的第一个任务，开始高效管理时间吧" }
    var noCompletedTasks: String { isEnglish ? "No completed tasks yet" : "还没有已完成的任务" }
    var completedWillShowHere: String { isEnglish ? "Completed tasks will show here, keep going!" : "完成的任务会显示在这里，继续加油！" }
    var noHabits: String { isEnglish ? "No habits yet" : "还没有习惯" }

    // MARK: - 使用说明

    var usageGuideOverview: String {
        isEnglish ? "FlowTakt is an all-in-one productivity tool combining Pomodoro focus, task management, habit tracking and time statistics to help you take control of your daily rhythm."
        : "FlowTakt 是一站式效率工具，融合番茄钟专注、任务管理、习惯追踪与时间统计，帮你掌控每一天的节奏。"
    }

    func guideContent(for module: String) -> String {
        switch module {
        case "focus":
            return isEnglish ? (
                "Start a focus session with a tap. Link a task to track what you're working on. "
                + "Focus sessions are divided into Pomodoro intervals with short and long breaks. "
                + "You can pause or skip phases at any time. "
                + "White noise is available to help you stay concentrated."
            ) : (
                "点击即可开始专注。关联任务可记录当前正在做什么。\n"
                + "专注会话按番茄钟分段，间隔短休息和长休息。\n"
                + "随时可以暂停或跳过当前阶段。\n"
                + "支持白噪音辅助集中注意力。"
            )

        case "task":
            return isEnglish ? (
                "Create tasks with priority levels (High / Medium / Low). "
                + "Split large tasks into subtasks to make progress manageable. "
                + "Filter tasks by priority or completion status. "
                + "Swipe left on a task to delete it."
            ) : (
                "创建任务时可设置优先级（高 / 中 / 低）。\n"
                + "大任务可以拆分成子任务，逐步完成。\n"
                + "按优先级或完成状态筛选任务。\n"
                + "左滑任务可删除。"
            )

        case "calendar":
            return isEnglish ? (
                "Switch between day and month views to see your schedule. "
                + "Tap a date to view or edit events for that day. "
                + "Color-code events by category for quick visual reference. "
                + "Supports both Gregorian and Lunar calendar displays."
            ) : (
                "在日视图和月视图之间切换查看日程。\n"
                + "点击日期可查看或编辑当天事件。\n"
                + "按类别为事件设置颜色，一目了然。\n"
                + "支持公历和农历显示。"
            )

        case "habit":
            return isEnglish ? (
                "Build small, consistent habits. Set a daily target count and track your streak. "
                + "Check off each day you complete the habit. "
                + "The app records your longest streak to keep you motivated."
            ) : (
                "培养小而持续的习惯。设置每日目标次数并追踪连续打卡。\n"
                + "每天完成后点击打卡即可记录。\n"
                + "应用会记录你的最长连续打卡天数，助你坚持。"
            )

        case "timer":
            return isEnglish ? (
                "A free-running timer for tracking activity duration. "
                + "Tap start to begin recording — no preset duration needed. "
                + "Optionally link a task and mark as billable. "
                + "Tap stop when done and the duration is saved to your records."
            ) : (
                "自由计时器，用于记录活动时长。\n"
                + "无需预设时长，点击即可开始计时。\n"
                + "可选关联任务并标记为计费项目。\n"
                + "完成后点击停止，时长自动保存到记录。"
            )

        case "stats":
            return isEnglish ? (
                "View your daily focus summary, weekly trend, and total points earned. "
                + "Each completed Pomodoro earns you points. "
                + "Unlock achievements by reaching milestones in focus time, streaks, and points."
            ) : (
                "查看每日专注概览、本周趋势和累计积分。\n"
                + "每完成一个番茄钟都能获得积分。\n"
                + "达到专注时长、连续打卡或积分里程碑时解锁成就。"
            )

        case "achievement":
            return isEnglish ? (
                "Earn points by completing focus sessions and unlock achievements. "
                + "Achievements are grouped into categories: Focus, Streak, and Points. "
                + "Tap an achievement to see its unlock condition."
            ) : (
                "完成专注会话赚取积分，解锁成就。\n"
                + "成就按类别分组：专注、连续打卡、积分。\n"
                + "点击成就可查看解锁条件。"
            )

        default:
            return ""
        }
    }

    var pomodoroTips: [String] {
        isEnglish ? [
            "① Focus on one thing at a time. Eliminate all distractions during focus sessions.",
            "② Always take a break after each pomodoro, even just standing up and stretching.",
            "③ If interrupted, note the reason and restart the current pomodoro.",
            "④ Don't exceed 8 pomodoros in a row to avoid cognitive fatigue.",
            "⑤ Review your stats daily to discover your peak productivity hours."
        ] : [
            "① 一次只做一件事，专注期间关闭所有干扰。",
            "② 每个番茄钟结束后务必休息，哪怕只是站起来走走。",
            "③ 如果被打断，记录中断原因，并重新开始当前番茄钟。",
            "④ 不要连续超过 8 个番茄钟，避免认知疲劳。",
            "⑤ 每天回顾统计页面，了解自己的高效时段。"
        ]
    }

    // MARK: - 本地化字符串键（用于 SwiftUI 视图）

    var 今日概览: String { isEnglish ? "Today's Overview" : "今日概览" }
    var 本周趋势: String { isEnglish ? "Weekly Trend" : "本周趋势" }
    var 一: String { isEnglish ? "Mon" : "一" }
    var 二: String { isEnglish ? "Tue" : "二" }
    var 三: String { isEnglish ? "Wed" : "三" }
    var 四: String { isEnglish ? "Thu" : "四" }
    var 五: String { isEnglish ? "Fri" : "五" }
    var 六: String { isEnglish ? "Sat" : "六" }
    var 日: String { isEnglish ? "Sun" : "日" }
    var 今日: String { isEnglish ? "Today" : "今天" }
    var 明日: String { isEnglish ? "Tomorrow" : "明天" }
    var 昨日: String { isEnglish ? "Yesterday" : "昨天" }

    var 全部: String { isEnglish ? "All" : "全部" }
    var 短休息: String { isEnglish ? "Short Break" : "短休息" }
    var 长休息: String { isEnglish ? "Long Break" : "长休息" }

    // MARK: - Tab 标签
    var focus: String { isEnglish ? "Focus" : "专注" }
    var plan: String { isEnglish ? "Plan" : "计划" }
    var stats: String { isEnglish ? "Stats" : "统计" }
    var habits: String { isEnglish ? "Habits" : "习惯" }
    var settings: String { isEnglish ? "Settings" : "设置" }

    // MARK: - 通用
    var 保存: String { isEnglish ? "Save" : "保存" }
    var 取消: String { isEnglish ? "Cancel" : "取消" }
    var 删除: String { isEnglish ? "Delete" : "删除" }
    var 确定: String { isEnglish ? "Confirm" : "确定" }
    var 好的: String { isEnglish ? "OK" : "好的" }
    var 完成: String { isEnglish ? "Complete" : "完成" }
    var 进行中: String { isEnglish ? "In Progress" : "进行中" }
    var 已计划: String { isEnglish ? "Planned" : "已计划" }
    var 已完成: String { isEnglish ? "Completed" : "已完成" }
    var 活跃: String { isEnglish ? "Active" : "活跃" }
    var 已中断: String { isEnglish ? "Interrupted" : "已中断" }
    var 已放弃: String { isEnglish ? "Abandoned" : "已放弃" }
    var 进度: String { isEnglish ? "Progress" : "进度" }
    var 状态: String { isEnglish ? "Status" : "状态" }
    var 无任务: String { isEnglish ? "No Task" : "无任务" }
    var 未分类: String { isEnglish ? "Uncategorized" : "未分类" }
    var 无关联任务: String { isEnglish ? "No Linked Task" : "无关联任务" }
    var 无可用任务: String { isEnglish ? "No Available Tasks" : "无可用任务" }

    // MARK: - 任务排序
    var 排序: String { isEnglish ? "Sort" : "排序" }
    var 按截止日期: String { isEnglish ? "Due Date" : "按截止日期" }
    var 按优先级: String { isEnglish ? "Priority" : "按优先级" }
    var 按创建时间: String { isEnglish ? "Created" : "按创建时间" }

    // MARK: - 中断原因（放弃番茄钟）
    var 中断原因: String { isEnglish ? "Interruption Reason" : "中断原因" }
    var 为什么中断了这个番茄: String { isEnglish ? "Why was this pomodoro interrupted?" : "为什么中断了这个番茄？" }
    var 原因电话: String { isEnglish ? "Phone call" : "电话" }
    var 原因临时有事: String { isEnglish ? "Something came up" : "临时有事" }
    var 原因身体不适: String { isEnglish ? "Not feeling well" : "身体不适" }
    var 原因想休息: String { isEnglish ? "Need a break" : "想休息一下" }
    var 原因其他: String { isEnglish ? "Other…" : "其他…" }

    // MARK: - 任务
    var 任务: String { isEnglish ? "Task" : "任务" }
    var 任务标题: String { isEnglish ? "Task Title" : "任务标题" }
    var 重复任务: String { isEnglish ? "Recurring Task" : "重复任务" }
    var 重复频率: String { isEnglish ? "Repeat Frequency" : "重复频率" }
    var 任务详情: String { isEnglish ? "Task Details" : "任务详情" }
    var 任务分解: String { isEnglish ? "Task Breakdown" : "任务分解" }
    var 新建任务: String { isEnglish ? "New Task" : "新建任务" }
    var 删除任务: String { isEnglish ? "Delete Task" : "删除任务" }
    var 优先级: String { isEnglish ? "Priority" : "优先级" }
    var 低优先: String { isEnglish ? "Low" : "低优先" }
    var 中优先: String { isEnglish ? "Medium" : "中优先" }
    var 高优先: String { isEnglish ? "High" : "高优先" }
    var 截止日期: String { isEnglish ? "Due Date" : "截止日期" }
    var 设置截止日期: String { isEnglish ? "Set Due Date" : "设置截止日期" }
    var 未设定日期: String { isEnglish ? "No Date Set" : "未设定日期" }
    var 关联任务: String { isEnglish ? "Linked Task" : "关联任务" }
    var 创建时间: String { isEnglish ? "Created" : "创建时间" }
    var 更新时间: String { isEnglish ? "Updated" : "更新时间" }
    var 完成时间: String { isEnglish ? "Completed" : "完成时间" }
    var 确认删除: String { isEnglish ? "Confirm Delete" : "确认删除" }

    // MARK: - 番茄钟 / 计时
    var 番茄钟: String { isEnglish ? "Pomodoro" : "番茄钟" }
    var 计时: String { isEnglish ? "Timer" : "计时" }
    var 开始计时: String { isEnglish ? "Start Timer" : "开始计时" }
    var 正在计时: String { isEnglish ? "Timing..." : "正在计时" }
    var 准备就绪: String { isEnglish ? "Ready" : "准备就绪" }
    var 已暂停: String { isEnglish ? "Paused" : "已暂停" }
    var 白噪音: String { isEnglish ? "White Noise" : "白噪音" }
    var 白噪音开: String { isEnglish ? "White Noise On" : "白噪音 开" }
    var 白噪音关: String { isEnglish ? "White Noise Off" : "白噪音 关" }
    var 白噪音类型: String { isEnglish ? "Noise Type" : "白噪音类型" }
    var 白噪音类型白: String { isEnglish ? "White Noise" : "白噪音" }
    var 白噪音类型雨: String { isEnglish ? "Rain" : "雨声" }
    var 白噪音类型溪流: String { isEnglish ? "Stream" : "溪流" }
    var 白噪音类型咖啡厅: String { isEnglish ? "Cafe" : "咖啡厅" }

    // MARK: - 沉浸 Hero 单页（v1.3 UI 升级：phase 标题 / 副标题 / 时长 chip）
    var 深度聚焦: String { isEnglish ? "Deep Focus" : "深度聚焦" }
    var 深度聚焦副标题: String { isEnglish ? "Just this one thing, right now" : "这一段，只做当下那一件事" }
    var 快速恢复: String { isEnglish ? "Quick Recharge" : "快速恢复" }
    var 快速恢复副标题: String { isEnglish ? "Stand up, grab a sip, look afar" : "起身倒杯水，眼睛看看远处" }
    var 彻底放空: String { isEnglish ? "Full Reset" : "彻底放空" }
    var 彻底放空副标题: String { isEnglish ? "Put the screen down, take a walk" : "放下屏幕，去走走或打个盹" }
    // 审查修复（2026-08-12 v1.3.4l）：时长预设 15/25/45 三个键删除（专注 Tab 已取消入口，仅保留「自定义」）
    var 时长预设自定义: String { isEnglish ? "Custom…" : "自定义…" }
    // 无障碍修复（2026-08-12）：时长 Menu 提示
    var 选择后立即开始专注: String { isEnglish ? "Starts immediately after selection" : "选择后立即开始" }
    var 长按时长手势提示: String { isEnglish ? "Long press to give up" : "长按放弃本次" }
    // 审查修复（2026-08-12 v1.3.4m）：删除 FocusPresetSheet 整页选择后，下面两键无引用
    var 恢复: String { isEnglish ? "Resume" : "恢复" }
    var 暂停: String { isEnglish ? "Pause" : "暂停" }
    var 停止: String { isEnglish ? "Stop" : "停止" }
    var 记录: String { isEnglish ? "Records" : "记录" }
    var 暂无记录: String { isEnglish ? "No Records" : "暂无记录" }
    var 未记录时间: String { isEnglish ? "No Time Recorded" : "未记录时间" }
    var 今日总计: String { isEnglish ? "Today Total" : "今日总计" }
    var 选择日期: String { isEnglish ? "Select Date" : "选择日期" }
    var 点击上方按钮开始计时: String { isEnglish ? "Tap the button above to start timing" : "点击上方按钮开始计时" }

    // MARK: - 计时设置
    var 计时设置: String { isEnglish ? "Timer Settings" : "计时设置" }
    var 专注时长: String { isEnglish ? "Focus Duration" : "专注时长" }
    var 短休息时长: String { isEnglish ? "Short Break Duration" : "短休息时长" }
    var 长休息时长: String { isEnglish ? "Long Break Duration" : "长休息时长" }
    var 长休息轮次: String { isEnglish ? "Long Break Interval" : "长休息轮次" }
    var 自动开始专注: String { isEnglish ? "Auto-start Focus" : "自动开始专注" }
    var 自动开始休息: String { isEnglish ? "Auto-start Break" : "自动开始休息" }

    // MARK: - 习惯
    var 习惯: String { isEnglish ? "Habits" : "习惯" }
    var 习惯名称: String { isEnglish ? "Habit Name" : "习惯名称" }
    var 新建习惯: String { isEnglish ? "New Habit" : "新建习惯" }
    var 建立一个小习惯: String { isEnglish ? "Build a small habit" : "建立一个小习惯" }
    var 创建第一个习惯: String { isEnglish ? "Create your first habit" : "创建第一个习惯" }
    var 频率: String { isEnglish ? "Frequency" : "频率" }
    var 每天: String { isEnglish ? "Daily" : "每天" }
    var 每周: String { isEnglish ? "Weekly" : "每周" }
    var 每月: String { isEnglish ? "Monthly" : "每月" }
    var 不重复: String { isEnglish ? "No Repeat" : "不重复" }
    var 工作日: String { isEnglish ? "Weekdays" : "工作日" }
    var 每两周: String { isEnglish ? "Biweekly" : "每两周" }
    var 每年: String { isEnglish ? "Yearly" : "每年" }
    var 每日目标次数: String { isEnglish ? "Daily Target" : "每日目标次数" }
    var 名称: String { isEnglish ? "Name" : "名称" }
    var 图标: String { isEnglish ? "Icon" : "图标" }
    var 颜色: String { isEnglish ? "Color" : "颜色" }
    var 当前状态: String { isEnglish ? "Current Status" : "当前状态" }
    var 连续专注: String { isEnglish ? "Streak" : "连续专注" }
    var 天: String { isEnglish ? "days" : "天" }

    // MARK: - 日程 / 事件
    var 事件标题: String { isEnglish ? "Event Title" : "事件标题" }
    var 时间: String { isEnglish ? "Time" : "时间" }
    var 开始: String { isEnglish ? "Start" : "开始" }
    var 结束: String { isEnglish ? "End" : "结束" }
    var 结束时间: String { isEnglish ? "End Time" : "结束时间" }
    var 全天: String { isEnglish ? "All Day" : "全天" }
    var 准时: String { isEnglish ? "On Time" : "准时" }
    func 提前分钟(_ minutes: Int) -> String { isEnglish ? "\(minutes) min before" : "提前 \(minutes) 分钟" }
    var 提前一小时: String { isEnglish ? "1 hour before" : "提前 1 小时" }
    var 提前一天: String { isEnglish ? "1 day before" : "提前 1 天" }
    var 提前两天: String { isEnglish ? "2 days before" : "提前 2 天" }
    var 提前一周: String { isEnglish ? "1 week before" : "提前 1 周" }
    var 地点: String { isEnglish ? "Location" : "地点" }
    var 备注: String { isEnglish ? "Notes" : "备注" }
    var 备注可选: String { isEnglish ? "Notes (Optional)" : "备注（可选）" }
    var 添加备注: String { isEnglish ? "Add Notes" : "添加备注" }
    var 新建事件: String { isEnglish ? "New Event" : "新建事件" }
    var 编辑事件: String { isEnglish ? "Edit Event" : "编辑事件" }
    var 当日无日程: String { isEnglish ? "No events today" : "当日无日程" }
    var 上一月: String { isEnglish ? "Previous Month" : "上一月" }
    var 下一月: String { isEnglish ? "Next Month" : "下一月" }
    var 日程: String { isEnglish ? "Schedule" : "日程" }

    // MARK: - 颜色名称
    var 红色: String { isEnglish ? "Red" : "红色" }
    var 蓝色: String { isEnglish ? "Blue" : "蓝色" }
    var 绿色: String { isEnglish ? "Green" : "绿色" }
    var 橙色: String { isEnglish ? "Orange" : "橙色" }
    var 紫色: String { isEnglish ? "Purple" : "紫色" }

    // MARK: - 统计
    var 统计: String { isEnglish ? "Stats" : "统计" }
    var 完成率: String { isEnglish ? "Completion Rate" : "完成率" }
    var 数据洞察: String { isEnglish ? "Data Insights" : "数据洞察" }
    var 模块说明: String { isEnglish ? "Module Instructions" : "模块说明" }
    var 效率建议: String { isEnglish ? "Efficiency Tips" : "效率建议" }
    var 番茄工作法小贴士: String { isEnglish ? "Pomodoro Technique Tips" : "番茄工作法小贴士" }

    // MARK: - 成就
    var 成就解锁: String { isEnglish ? "Achievement Unlocked" : "成就解锁" }
    var 成就: String { isEnglish ? "Achievements" : "成就" }

    // MARK: - 设置
    var 设置: String { isEnglish ? "Settings" : "设置" }
    var 关于: String { isEnglish ? "About" : "关于" }
    var 使用说明: String { isEnglish ? "Usage Guide" : "使用说明" }
    // v1.3.4p：设置页评分入口
    var 在AppStore评分: String { isEnglish ? "Rate on App Store" : "在App Store评分" }
    // 无障碍（2026-08-17）：评分按钮 hint
    var 打开AppStore评分: String { isEnglish ? "Opens the App Store to rate this app" : "打开 App Store 为应用评分" }
    var 应用名称: String { isEnglish ? "App Name" : "应用名称" }
    var 版本: String { isEnglish ? "Version" : "版本" }
    var 语言: String { isEnglish ? "Language" : "语言" }

    // MARK: - 外观
    var 外观: String { isEnglish ? "Appearance" : "外观" }
    var 颜色主题: String { isEnglish ? "Color Theme" : "颜色主题" }
    var 跟随系统: String { isEnglish ? "Follow System" : "跟随系统" }
    var 浅色模式: String { isEnglish ? "Light" : "浅色模式" }
    var 深色模式: String { isEnglish ? "Dark" : "深色模式" }

    // MARK: - 同步与数据
    var 同步与数据: String { isEnglish ? "Sync & Data" : "同步与数据" }
    var iCloud同步: String { isEnglish ? "iCloud Sync" : "iCloud 同步" }
    var 立即同步: String { isEnglish ? "Sync Now" : "立即同步" }
    var iCloud同步说明: String { isEnglish ? "Enable iCloud to sync data across devices via CloudKit. Requires app restart to take effect." : "开启 iCloud 同步后，需重新启动 App 方可生效，数据将通过 CloudKit 在多台设备间同步" }
    var 同步已触发: String { isEnglish ? "Sync request sent — changes will sync to iCloud" : "同步请求已发送" }
    var 同步需先开启iCloud: String { isEnglish ? "Please enable iCloud Sync first" : "请先开启 iCloud 同步开关" }
    var 每日提醒: String { isEnglish ? "Daily Reminder" : "每日提醒" }
    var 每日提醒标题: String { isEnglish ? "Don't forget to focus today!" : "今天别忘了专注哦！" }
    var 每日提醒内容: String { isEnglish ? "Start your first pomodoro and have a productive day 🍅" : "开启今天的第一个番茄钟，开始高效的一天 🍅" }
    var 习惯打卡提醒: String { isEnglish ? "Habit Reminder" : "习惯打卡提醒" }
    var 习惯打卡提醒标题: String { isEnglish ? "Time to check in your habits!" : "该打卡啦！" }
    var 习惯打卡提醒内容: String { isEnglish ? "Keep the streak alive — check in your habits today 💪" : "今天也别忘了坚持习惯，保持连续打卡 💪" }
    var 提醒时间: String { isEnglish ? "Reminder Time" : "提醒时间" }
    var 重置数据库: String { isEnglish ? "Reset Database" : "重置数据库" }
    // 审查修复（2026-08-12）：补真实翻译；同时提示 iCloud 同步开启时云端旧数据会回灌（P1 #7）
    var 重置数据库确认提示: String { isEnglish ? "All local data will be permanently erased. Continue?" : "本地全部数据将被永久清除，确定继续吗？" }
    var 重置数据库成功提示: String { isEnglish ? "Database reset successfully" : "数据库重置成功" }
    var 重置数据库失败提示: String { isEnglish ? "Database reset failed" : "数据库重置失败" }
    var 确认重置: String { isEnglish ? "Confirm Reset" : "确认重置" }
    var 重置成功: String { isEnglish ? "Reset Successful" : "重置成功" }
    var 重置失败: String { isEnglish ? "Reset Failed" : "重置失败" }

    // MARK: - 声音与震动
    var 声音与震动: String { isEnglish ? "Sound & Haptics" : "声音与震动" }
    var 音效: String { isEnglish ? "Sound Effects" : "音效" }
    var 震动反馈: String { isEnglish ? "Haptic Feedback" : "震动反馈" }
    var 专注与休息切换时的提示音: String { isEnglish ? "Sound when switching focus/break" : "专注与休息切换时的提示音" }
    var 计时结束时的震动提醒: String { isEnglish ? "Vibration when timer ends" : "计时结束时的震动提醒" }
    var 语音播报: String { isEnglish ? "Voice Announcement" : "语音播报" }
    var 语音播报说明: String { isEnglish ? "Announce \"Pomodoro N completed\" when a focus session ends" : "专注结束时语音播报「第 N 个番茄完成」" }

    // MARK: - 通知
    var 专注结束: String { isEnglish ? "Focus Session Ended" : "专注结束" }
    func 番茄钟已完成(_ title: String) -> String {
        isEnglish ? "Pomodoro \"\(title)\" completed!" : "「\(title)」的番茄钟已完成！"
    }
    /// 任务番茄进度（如 1/4）
    func 番茄进度(_ completed: Int, _ estimated: Int) -> String {
        isEnglish ? "\(completed)/\(estimated) pomodoros" : "\(completed)/\(estimated) 番茄"
    }

    func 第X个番茄完成(_ index: Int) -> String {
        isEnglish ? "Pomodoro \(index) completed" : "第 \(index) 个番茄完成"
    }

    // MARK: - 错误提示
    func 数据保存失败(_ error: String) -> String {
        isEnglish ? "Save failed: \(error)" : "数据保存失败：\(error)"
    }
    func iCloud同步失败(_ error: String) -> String {
        isEnglish ? "iCloud sync failed: \(error)" : "iCloud 同步失败：\(error)"
    }
    var 通知权限被拒绝: String { isEnglish ? "Notification permission denied. Please enable it in Settings." : "通知权限被拒绝，请在设置中开启" }

    // MARK: - 提醒（生日 / 纪念日 / 客户拜访）

    var 类型: String { isEnglish ? "Type" : "类型" }
    var 提醒: String { isEnglish ? "Reminder" : "提醒" }
    var 提前提醒: String { isEnglish ? "Remind" : "提前提醒" }
    var 提醒设置标题: String { isEnglish ? "Reminder Settings" : "提醒设置" }
    var 提醒设置说明: String {
        isEnglish
        ? "Enable reminders for birthdays, anniversaries and client visits. Yearly items repeat automatically; one-time visits notify once."
        : "为生日、纪念日与客户拜访开启提醒。生日/纪念日每年自动重复，客户拜访为一次性提醒。"
    }
    var 已开启提醒: String { isEnglish ? "Reminder enabled" : "已开启提醒" }

    // MARK: - 提醒与通知设置

    var 提醒与通知: String { isEnglish ? "Reminders & Notifications" : "提醒与通知" }
    var 通知权限: String { isEnglish ? "Notification Permission" : "通知权限" }
    var 通知已授权: String { isEnglish ? "Authorized" : "已授权" }
    var 通知未授权: String { isEnglish ? "Not Authorized" : "未授权" }
    var 通知尚未请求: String { isEnglish ? "Not Determined" : "尚未请求" }
    var 去设置: String { isEnglish ? "Open Settings" : "去设置" }
    var 后台App刷新: String { isEnglish ? "Background App Refresh" : "后台 App 刷新" }
    var 后台刷新可用: String { isEnglish ? "Available" : "可用" }
    var 后台刷新不可用: String { isEnglish ? "Unavailable" : "不可用" }
    var 后台刷新受限: String { isEnglish ? "Restricted" : "受限" }
    var 后台刷新说明: String {
        isEnglish
        ? "The widget refreshes automatically via WidgetKit. Background App Refresh is a system setting (Settings → General → Background App Refresh) and cannot be requested in-app."
        : "小组件通过 WidgetKit 自动刷新。后台 App 刷新是系统级设置（设置 → 通用 → 后台 App 刷新），无法在 App 内请求授权。"
    }
    var 添加小组件说明: String {
        isEnglish
        ? "Long-press the home screen → Edit → tap + to add the FlowTakt Reminder widget."
        : "长按主屏幕 → 编辑 → 点 + 添加 FlowTakt 提醒小组件，即可在桌面查看临近的生日、纪念日与客户拜访。"
    }
    var 刷新小组件: String { isEnglish ? "Refresh Widget Now" : "立即刷新小组件" }
    var 计时器状态异常: String { isEnglish ? "Timer state invalid" : "计时器状态异常" }
    var 未找到专注会话: String { isEnglish ? "Focus session not found" : "未找到专注会话" }
    var 未找到任务: String { isEnglish ? "Task not found" : "未找到任务" }
    var 无法获取持久化存储URL: String { isEnglish ? "Unable to get persistent store URL" : "无法获取持久化存储 URL" }

    // MARK: - 时间格式
    func 小时分钟(_ hours: Int, _ minutes: Int) -> String {
        isEnglish ? "\(hours)h \(minutes)m" : "\(hours)小时\(minutes)分钟"
    }
    func 小时(_ hours: Int) -> String {
        isEnglish ? "\(hours)h" : "\(hours)小时"
    }
    func 分钟(_ minutes: Int) -> String {
        isEnglish ? "\(minutes)m" : "\(minutes)分钟"
    }
    /// 审查修复（2026-08-12）：设置页长休息轮次文案（原硬编码在 TimerSettingsSection）
    func 每X轮后(_ rounds: Int) -> String {
        isEnglish ? "After \(rounds) rounds" : "每 \(rounds) 轮后"
    }
    /// 计时器 VoiceOver 友好时间（如 "剩余 24 分 59 秒"）
    func 计时剩余(_ minutes: Int, _ seconds: Int) -> String {
        isEnglish ? "\(minutes) minutes \(seconds) seconds remaining" : "剩余 \(minutes) 分 \(seconds) 秒"
    }
    func 分秒(_ minutes: Int, _ seconds: Int) -> String {
        isEnglish ? "\(minutes)m \(seconds)s" : "\(minutes)分\(seconds)秒"
    }

    // MARK: - 成就
    func 恭喜解锁(_ title: String) -> String {
        isEnglish ? "Congratulations! Unlocked \"\(title)\"!" : "恭喜解锁「\(title)」！"
    }

    // MARK: - 隐私政策
    var 隐私政策: String { isEnglish ? "Privacy Policy" : "隐私政策" }
    var 最后更新日期: String { isEnglish ? "Last updated: August 7, 2026" : "最后更新日期：2026年8月7日" }

    var 隐私引言: String {
        isEnglish
        ? "FlowTakt values your privacy. This policy explains how we handle your data."
        : "FlowTakt 重视你的隐私。本政策说明我们如何处理你的数据。"
    }

    var 信息收集标题: String { isEnglish ? "1. Information Collection" : "1. 信息收集" }
    var 信息收集内容: String {
        isEnglish
        ? ("We do not collect, transmit, or store any of your personal data on external servers. "
           + "All data you create within FlowTakt — including tasks, schedules, focus sessions, "
           + "habits, and achievement records — is stored exclusively on your device using Apple's "
           + "Core Data framework. We have no access to any of your data.")
        : ("我们不会在任何外部服务器上收集、传输或存储你的个人数据。"
           + "你在 FlowTakt 中创建的所有数据——包括任务、日程、专注会话、"
           + "习惯和成就记录——仅存储在你的设备上，使用 Apple 的 Core Data 框架。"
           + "我们无法访问你的任何数据。")
    }

    var 信息使用标题: String { isEnglish ? "2. Information Usage" : "2. 信息使用" }
    var 信息使用内容: String {
        isEnglish
        ? ("Your data is used solely to provide the app's core functionality: "
           + "displaying tasks, tracking focus sessions, recording habits, showing statistics, "
           + "and unlocking achievements. All data processing happens locally on your device.")
        : ("你的数据仅用于提供 App 的核心功能：显示任务、追踪专注会话、"
           + "记录习惯、展示统计数据和解锁成就。所有数据处理均在设备本地完成。")
    }

    var 数据存储标题: String { isEnglish ? "3. Data Storage" : "3. 数据存储" }
    var 数据存储内容: String {
        isEnglish
        ? ("All your data is stored locally on your device using Core Data and, if enabled, "
           + "synced via Apple's iCloud service. iCloud sync is end-to-end encrypted and "
           + "we do not have access to your iCloud data.")
        : ("你的所有数据均使用 Core Data 存储在设备本地，如果启用 iCloud 同步，"
           + "则会通过 Apple 的 iCloud 服务同步。iCloud 同步采用端到端加密，"
           + "我们无法访问你的 iCloud 数据。")
    }

    var iCloud同步标题: String { isEnglish ? "4. iCloud Sync" : "4. iCloud 同步" }
    var iCloud同步内容: String {
        isEnglish
        ? ("FlowTakt offers optional iCloud sync to keep your data consistent across your "
           + "Apple devices. When enabled, your data is synced via your personal iCloud "
           + "account using Apple's CloudKit framework. The sync process is managed entirely "
           + "by Apple, and we do not have access to any data transmitted through iCloud. "
           + "You can disable iCloud sync at any time in Settings.")
        : ("FlowTakt 提供可选的 iCloud 同步功能，使你的数据在 Apple 设备间保持一致。"
           + "启用后，你的数据通过个人 iCloud 账户使用 Apple 的 CloudKit 框架进行同步。"
           + "同步过程完全由 Apple 管理，我们无法访问通过 iCloud 传输的任何数据。"
           + "你可以在设置中随时关闭 iCloud 同步。")
    }

    var 通知权限标题: String { isEnglish ? "5. Notifications" : "5. 通知权限" }
    var 通知权限内容: String {
        isEnglish
        ? ("FlowTakt may request permission to send you local notifications for focus "
           + "session completion, daily reminders, and habit tracking. All notifications "
           + "are generated locally on your device. No notification data is sent to any server.")
        : ("FlowTakt 可能会请求发送本地通知的权限，用于专注会话完成提醒、每日提醒"
           + "和习惯追踪。所有通知均在设备本地生成，不会向任何服务器发送通知数据。")
    }

    var 第三方服务标题: String { isEnglish ? "6. Third-Party Services" : "6. 第三方服务" }
    var 第三方服务内容: String {
        isEnglish
        ? ("FlowTakt does not integrate any third-party analytics, advertising, or tracking "
           + "services. The only external service used is Apple's iCloud (optional), "
           + "which is governed by Apple's own privacy policy.")
        : ("FlowTakt 不集成任何第三方分析、广告或追踪服务。"
           + "唯一使用的外部服务是 Apple 的 iCloud（可选），"
           + "该服务受 Apple 自身隐私政策的约束。")
    }

    var 用户权利标题: String { isEnglish ? "7. Your Rights" : "7. 你的权利" }
    var 用户权利内容: String {
        isEnglish
        ? ("Since all data is stored locally on your device, you have full control. "
           + "You can view, modify, or delete all your data at any time through the app. "
           + "You can also reset all data via Settings > Reset Database. "
           + "Uninstalling the app will permanently delete all locally stored data.")
        : ("由于所有数据均存储在设备本地，你拥有完全的控制权。"
           + "你可以随时通过 App 查看、修改或删除所有数据。"
           + "也可以通过 设置 > 重置数据库 来清除所有数据。"
           + "卸载 App 将永久删除所有本地存储的数据。")
    }

    var 儿童隐私标题: String { isEnglish ? "8. Children's Privacy" : "8. 儿童隐私" }
    var 儿童隐私内容: String {
        isEnglish
        ? ("FlowTakt is not directed to children under the age of 13. We do not knowingly "
           + "collect personal information from children. If you believe a child has provided "
           + "us with personal information, please contact us.")
        : ("FlowTakt 不面向 13 岁以下的儿童。我们不会有意收集儿童的个人信息。"
           + "如果你认为儿童向我们提供了个人信息，请联系我们。")
    }

    var 政策变更标题: String { isEnglish ? "9. Policy Changes" : "9. 政策变更" }
    var 政策变更内容: String {
        isEnglish
        ? ("We may update this privacy policy from time to time. Any changes will be "
           + "reflected in the app and the updated date at the top of this page. "
           + "We encourage you to review this policy periodically.")
        : ("我们可能会不时更新本隐私政策。任何变更将在 App 中体现，"
           + "并更新本页面顶部的日期。建议你定期查看本政策。")
    }

    var 联系我们标题: String { isEnglish ? "10. Contact Us" : "10. 联系我们" }
    var 联系我们内容: String {
        isEnglish
        ? ("If you have any questions about this privacy policy or our data practices, "
           + "please contact us at: 33888833@qq.com (QQ: 33888833)")
        : ("如果你对本隐私政策或数据处理有任何疑问，"
           + "请通过以下方式联系我们：33888833@qq.com  QQ：33888833")
    }

    // MARK: - v1.3 新增文案

    // 周报推送
    var 本周专注周报: String { isEnglish ? "Weekly Focus Report" : "本周专注周报" }
    var 本周专注周报内容: String { isEnglish ? "Your weekly focus summary is ready." : "你的本周专注周报已生成。" }
    func 周报汇总(pomodoros: Int, minutes: Int, streak: Int) -> String {
        isEnglish
        ? "\(pomodoros) pomodoros · \(minutes) min focused · \(streak)-day streak"
        : "本周完成 \(pomodoros) 个番茄钟 · 专注 \(minutes) 分钟 · 连续 \(streak) 天"
    }
    var 每周日周报: String { isEnglish ? "Weekly Report" : "每周日周报" }
    var 每周日周报说明: String {
        isEnglish
        ? "Get a Sunday evening summary of your week's focus time, completed pomodoros and streak."
        : "每周日晚推送本周专注时长、完成番茄数与连续天数。"
    }

    // 任务归档检索
    var 归档: String { isEnglish ? "Archived" : "归档" }
    var 暂无归档任务: String { isEnglish ? "No archived tasks" : "暂无归档任务" }
    var 归档任务为空说明: String {
        isEnglish
        ? "Completed tasks you archive are kept here and can be restored anytime."
        : "已完成的任务归档后会被保留在此，可随时恢复。"
    }
    var 搜索归档任务: String { isEnglish ? "Search archived tasks" : "搜索归档任务" }

    // 习惯打卡热力图
    var 打卡热力图: String { isEnglish ? "Check-in Heatmap" : "打卡热力图" }
    var 热力图: String { isEnglish ? "Heatmap" : "热力图" }
    var 打卡次数: String { isEnglish ? "Check-ins" : "打卡次数" }
    var 打卡天数: String { isEnglish ? "Active Days" : "打卡天数" }
    // 无障碍修复（2026-08-12）：打卡按钮 VoiceOver 标签
    var 打卡: String { isEnglish ? "Check in" : "打卡" }
    var 热力图图例: String { isEnglish ? "Less" : "少" }

    // 数据导出
    var 数据导出: String { isEnglish ? "Export Data" : "数据导出" }
    var 导出数据: String { isEnglish ? "Export CSV" : "导出数据" }
    var 导出失败提示: String { isEnglish ? "Export failed" : "导出失败" }

    // 今日专注（锁屏 Widget）
}

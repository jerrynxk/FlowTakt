import Foundation
import SwiftUI
import Combine

// MARK: - 运行时英文本地化（ObservableObject 单例，支持 SwiftUI 响应式刷新）

final class L10n: ObservableObject {
    static let shared = L10n()

    @Published var appLanguage: String = UserDefaults.standard.string(forKey: "appLanguage") ?? "zh-Hans"

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

    func todayPoints(_ pts: Int) -> String {
        isEnglish ? "+\(pts) Points" : "+\(pts) 积分"
    }

    func estimatedPomodoros(_ count: Int) -> String {
        isEnglish ? "\(count) pomodoros" : "\(count) 个番茄钟"
    }

    func habitToday(_ count: Int, target: Int16) -> String {
        isEnglish ? "Today \(count)/\(target)" : "今日 \(count)/\(target)"
    }

    func targetCount(_ count: Int) -> String {
        isEnglish ? "\(count) times" : "\(count) 次"
    }

    func minutes(_ mins: Int) -> String {
        isEnglish ? "\(mins) min" : "\(mins) 分钟"
    }

    func everyNRounds(_ n: Int) -> String {
        isEnglish ? "Every \(n) rounds" : "每 \(n) 轮后"
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
    var createFirstHabit: String { isEnglish ? "Build a small habit and stick with it. Time will reward you." : "建立一个小习惯，坚持下去，时间会给你最好的答案" }

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
                + "Check off each completion in the timer tab. "
                + "The app records your longest streak to keep you motivated."
            ) : (
                "培养小而持续的习惯。设置每日目标次数并追踪连续打卡。\n"
                + "在计时标签页中每次完成即可打卡。\n"
                + "应用会记录你的最长连续打卡天数，助你坚持。"
            )

        case "timer":
            return isEnglish ? (
                "A standalone timer for activities that don't fit the Pomodoro format. "
                + "Set a custom duration and tap start. "
                + "The timer runs in the background and notifies you when time is up."
            ) : (
                "独立计时器，适用于不适合番茄钟格式的活动。\n"
                + "自定义时长后点击开始。\n"
                + "计时器在后台运行，时间到时会通知你。"
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
    var 无关联任务: String { isEnglish ? "No Linked Task" : "无关联任务" }
    var 无可用任务: String { isEnglish ? "No Available Tasks" : "无可用任务" }

    // MARK: - 任务
    var 任务: String { isEnglish ? "Task" : "任务" }
    var 任务标题: String { isEnglish ? "Task Title" : "任务标题" }
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

    // MARK: - 番茄钟 / 计时
    var 番茄钟: String { isEnglish ? "Pomodoro" : "番茄钟" }
    var 计时: String { isEnglish ? "Timer" : "计时" }
    var 开始计时: String { isEnglish ? "Start Timer" : "开始计时" }
    var 正在计时: String { isEnglish ? "Timing..." : "正在计时" }
    var 准备就绪: String { isEnglish ? "Ready" : "准备就绪" }
    var 已暂停: String { isEnglish ? "Paused" : "已暂停" }
    var 白噪音开: String { isEnglish ? "White Noise On" : "白噪音 开" }
    var 白噪音关: String { isEnglish ? "White Noise Off" : "白噪音 关" }
    var 恢复: String { isEnglish ? "Resume" : "恢复" }
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
    var 还没有习惯: String { isEnglish ? "No habits yet" : "还没有习惯" }
    var 频率: String { isEnglish ? "Frequency" : "频率" }
    var 每天: String { isEnglish ? "Daily" : "每天" }
    var 每周: String { isEnglish ? "Weekly" : "每周" }
    var 每月: String { isEnglish ? "Monthly" : "每月" }
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
    var 地点: String { isEnglish ? "Location" : "地点" }
    var 备注: String { isEnglish ? "Notes" : "备注" }
    var 备注可选: String { isEnglish ? "Notes (Optional)" : "备注（可选）" }
    var 添加备注: String { isEnglish ? "Add Notes" : "添加备注" }
    var 新建事件: String { isEnglish ? "New Event" : "新建事件" }
    var 编辑事件: String { isEnglish ? "Edit Event" : "编辑事件" }
    var 当日无日程: String { isEnglish ? "No events today" : "当日无日程" }
    var 日程: String { isEnglish ? "Schedule" : "日程" }

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
    var 应用名称: String { isEnglish ? "App Name" : "应用名称" }
    var 版本: String { isEnglish ? "Version" : "版本" }
    var 语言: String { isEnglish ? "Language" : "语言" }

    // MARK: - 同步与数据
    var 同步与数据: String { isEnglish ? "Sync & Data" : "同步与数据" }
    var iCloud同步: String { isEnglish ? "iCloud Sync" : "iCloud 同步" }
    var 每日提醒: String { isEnglish ? "Daily Reminder" : "每日提醒" }
    var 每日提醒标题: String { isEnglish ? "Don't forget to focus today!" : "今天别忘了专注哦！" }
    var 每日提醒内容: String { isEnglish ? "Start your first pomodoro and have a productive day 🍅" : "开启今天的第一个番茄钟，开始高效的一天 🍅" }
    var 提醒时间: String { isEnglish ? "Reminder Time" : "提醒时间" }
    var 重置数据库: String { isEnglish ? "Reset Database" : "重置数据库" }
    var 重置数据库提示: String { isEnglish ? "Reset Database" : "重置数据库提示" }
    var 重置数据库确认提示: String { isEnglish ? "Confirm reset database" : "重置数据库确认提示" }
    var 重置数据库成功提示: String { isEnglish ? "Database reset successfully" : "数据库重置成功提示" }
    var 重置数据库失败提示: String { isEnglish ? "Database reset failed" : "数据库重置失败提示" }
    var 确认重置: String { isEnglish ? "Confirm Reset" : "确认重置" }
    var 重置成功: String { isEnglish ? "Reset Successful" : "重置成功" }
    var 重置失败: String { isEnglish ? "Reset Failed" : "重置失败" }

    // MARK: - 声音与震动
    var 声音与震动: String { isEnglish ? "Sound & Haptics" : "声音与震动" }
    var 音效: String { isEnglish ? "Sound Effects" : "音效" }
    var 震动反馈: String { isEnglish ? "Haptic Feedback" : "震动反馈" }
    var 专注与休息切换时的提示音: String { isEnglish ? "Sound when switching focus/break" : "专注与休息切换时的提示音" }
    var 计时结束时的震动提醒: String { isEnglish ? "Vibration when timer ends" : "计时结束时的震动提醒" }

    // MARK: - 通知
    var 专注结束: String { isEnglish ? "Focus Session Ended" : "专注结束" }
    func 番茄钟已完成(_ title: String) -> String {
        isEnglish ? "Pomodoro \"\(title)\" completed!" : "「\(title)」的番茄钟已完成！"
    }

    // MARK: - 错误提示
    func 数据保存失败(_ error: String) -> String {
        isEnglish ? "Save failed: \(error)" : "数据保存失败：\(error)"
    }
    func iCloud同步失败(_ error: String) -> String {
        isEnglish ? "iCloud sync failed: \(error)" : "iCloud 同步失败：\(error)"
    }
    var 通知权限被拒绝: String { isEnglish ? "Notification permission denied. Please enable it in Settings." : "通知权限被拒绝，请在设置中开启" }
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
    func 分秒(_ minutes: Int, _ seconds: Int) -> String {
        isEnglish ? "\(minutes)m \(seconds)s" : "\(minutes)分\(seconds)秒"
    }

    // MARK: - 成就
    func 恭喜解锁(_ title: String) -> String {
        isEnglish ? "Congratulations! Unlocked \"\(title)\"!" : "恭喜解锁「\(title)」！"
    }

    // MARK: - 隐私政策
    var 隐私政策: String { isEnglish ? "Privacy Policy" : "隐私政策" }
    var 最后更新日期: String { isEnglish ? "Last updated: June 10, 2026" : "最后更新日期：2026年6月10日" }

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
           + "please contact us at: dlyzh_0303@qq.com")
        : ("如果你对本隐私政策或数据处理有任何疑问，"
           + "请通过以下方式联系我们：dlyzh_0303@qq.com")
    }
}

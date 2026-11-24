import Foundation
import AppIntents

// MARK: - FlowTakt AppIntents（快捷指令 / Siri）
//
// 文件分工（2026-10-14）：
// - 本文件（App 专属）：需要访问 AppDependency 的「工作流型」意图 ——
//   开始专注/休息、新建任务、习惯打卡、今日统计、打开页面。
// - FlowTaktShared/FocusControlIntents.swift（App+Widget 共享）：
//   暂停/继续/停止 —— 灵动岛按钮要求类型对 Widget 可见，且经 FocusControlBridge
//   解耦（Widget 模块中不存在 AppDependency 类型）。
//
// 注意：不要给 intent 结构体标注 @MainActor —— AppIntent.perform 本身在 main actor
// 上执行，标注会与 AppShortcutsProvider（nonisolated）冲突并产生并发警告。

// MARK: 开始专注

struct StartFocusIntent: AppIntent {
    static var title: LocalizedStringResource = "开始专注"
    static var description = IntentDescription("开始一个番茄钟专注时段")

    /// 专注时长（分钟），快捷指令中可配置
    @Parameter(title: "时长（分钟）", default: 25)
    var minutes: Int

    static var parameterSummary: some ParameterSummary {
        Summary("开始 \(\.$minutes) 分钟专注")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let dependency = AppDependency.shared else {
            return .result()
        }
        let clamped = min(max(1, minutes), 480)   // 钳制 1...480 分钟（审查 #18）
        let duration = TimeInterval(clamped * 60)
        dependency.focusViewModel.startFocus(phase: .focus, durationOverride: duration)
        return .result()
    }
}

// MARK: 开始休息

enum BreakKindOption: String, AppEnum {
    case short
    case long

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "休息类型")
    static var caseDisplayRepresentations: [BreakKindOption: DisplayRepresentation] = [
        .short: DisplayRepresentation(title: "短休息", image: .init(systemName: "cup.and.saucer.fill")),
        .long:  DisplayRepresentation(title: "长休息", image: .init(systemName: "moon.stars.fill")),
    ]
}

struct StartBreakIntent: AppIntent {
    static var title: LocalizedStringResource = "开始休息"
    static var description = IntentDescription("开始一段短休息或长休息")

    @Parameter(title: "类型", default: BreakKindOption.short)
    var kind: BreakKindOption

    /// 可选自定义时长（分钟）；不填则用设置中的默认时长
    @Parameter(title: "时长（分钟，可选）")
    var minutes: Int?

    static var parameterSummary: some ParameterSummary {
        Summary("开始 \(\.$kind)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let dependency = AppDependency.shared else {
            return .result()
        }
        let phase: FocusPhase = (kind == .short) ? .shortBreak : .longBreak
        var duration: TimeInterval? = nil
        if let minutes {
            duration = TimeInterval(min(max(1, minutes), 480) * 60)
        }
        dependency.focusViewModel.startFocus(phase: phase, durationOverride: duration)
        return .result()
    }
}

// MARK: 新建任务

enum TaskPriorityOption: Int, AppEnum {
    case low = 1
    case medium = 2
    case high = 3

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "优先级")
    static var caseDisplayRepresentations: [TaskPriorityOption: DisplayRepresentation] = [
        .high:   DisplayRepresentation(title: "高"),
        .medium: DisplayRepresentation(title: "中"),
        .low:    DisplayRepresentation(title: "低"),
    ]
}

struct AddTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "新建任务"
    static var description = IntentDescription("在 FlowTakt 中创建一个新任务")

    @Parameter(title: "任务标题")
    var title: String

    @Parameter(title: "优先级", default: TaskPriorityOption.medium)
    var priority: TaskPriorityOption

    @Parameter(title: "截止日期")
    var dueDate: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("新建任务 \(\.$title)") {
            \.$priority
            \.$dueDate
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let dependency = AppDependency.shared else {
            return .result(dialog: IntentDialog(stringLiteral: L10n.shared.数据未就绪提示))
        }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .result(dialog: IntentDialog(stringLiteral: L10n.shared.任务标题不能为空))
        }
        dependency.taskViewModel.createTask(
            title: trimmed,
            notes: nil,
            estimatedPomodoros: 1,
            priority: Int16(priority.rawValue),
            dueDate: dueDate
        )
        return .result(dialog: IntentDialog(stringLiteral: L10n.shared.已创建任务(trimmed)))
    }
}

// MARK: 习惯打卡

struct HabitEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "习惯")
    static var defaultQuery = HabitEntityQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct HabitEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [HabitEntity] {
        await MainActor.run {
            Self.allEntities().filter { identifiers.contains($0.id) }
        }
    }

    func suggestedEntities() async throws -> [HabitEntity] {
        await MainActor.run { Self.allEntities() }
    }

    /// 从运行中的 AppDependency 读取习惯列表（perform/查询均在主线程访问）
    @MainActor
    static func allEntities() -> [HabitEntity] {
        guard let vm = AppDependency.shared?.habitViewModel else { return [] }
        vm.loadHabits()
        return vm.habits.map { HabitEntity(id: $0.id.uuidString, name: $0.name) }
    }
}

struct CheckInHabitIntent: AppIntent {
    static var title: LocalizedStringResource = "习惯打卡"
    static var description = IntentDescription("为指定习惯完成今日打卡")

    @Parameter(title: "习惯")
    var habit: HabitEntity

    static var parameterSummary: some ParameterSummary {
        Summary("为 \(\.$habit) 打卡")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let vm = AppDependency.shared?.habitViewModel else {
            return .result(dialog: IntentDialog(stringLiteral: L10n.shared.数据未就绪提示))
        }
        vm.loadHabits()
        guard let target = vm.habits.first(where: { $0.id.uuidString == habit.id }) else {
            return .result(dialog: IntentDialog(stringLiteral: L10n.shared.无习惯可打卡))
        }
        if vm.dayHasRecord(habit: target, date: Date()) {
            return .result(dialog: IntentDialog(stringLiteral: L10n.shared.习惯今日已打卡(target.name)))
        }
        vm.checkIn(habit: target)
        return .result(dialog: IntentDialog(stringLiteral: L10n.shared.习惯已打卡(target.name)))
    }
}

// MARK: 今日专注统计

struct TodayStatsIntent: AppIntent {
    static var title: LocalizedStringResource = "查看今日统计"
    static var description = IntentDescription("读取今天的专注完成数、专注时长与积分")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let vm = AppDependency.shared?.statsViewModel else {
            return .result(dialog: IntentDialog(stringLiteral: L10n.shared.数据未就绪提示))
        }
        vm.refresh()
        let completed = vm.todaySessions.filter { $0.isCompleted }.count
        let minutes = Int(vm.todaySessions.reduce(0) { $0 + $1.actualDuration } / 60)
        let points = Int(vm.todaySessions.reduce(0) { $0 + $1.earnedPoints })
        return .result(dialog: IntentDialog(stringLiteral: L10n.shared.今日专注摘要(
            pomodoros: completed, minutes: minutes, points: points
        )))
    }
}

// MARK: 打开页面

enum AppPageOption: String, AppEnum {
    case focus
    case tasks
    case schedule
    case habits
    case stats
    case settings

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "页面")
    static var caseDisplayRepresentations: [AppPageOption: DisplayRepresentation] = [
        .focus:    DisplayRepresentation(title: "专注"),
        .tasks:    DisplayRepresentation(title: "任务"),
        .schedule: DisplayRepresentation(title: "日程"),
        .habits:   DisplayRepresentation(title: "习惯"),
        .stats:    DisplayRepresentation(title: "统计"),
        .settings: DisplayRepresentation(title: "设置"),
    ]
}

struct OpenPageIntent: AppIntent {
    static var title: LocalizedStringResource = "打开页面"
    static var description = IntentDescription("直接打开 FlowTakt 的指定页面")
    /// 打开页面需要前台展示 → 执行时将 App 带到前台
    static var openAppWhenRun: Bool = true

    @Parameter(title: "页面", default: AppPageOption.focus)
    var page: AppPageOption

    static var parameterSummary: some ParameterSummary {
        Summary("打开 \(\.$page) 页面")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let dependency = AppDependency.shared else {
            // 修复（2026-10-15 审查 P1-020）：Siri 冷启动竞态——App 依赖容器尚未就绪
            // 时直接返回会让 App 停在默认页。把意图落盘，AppDependency 初始化时消费。
            UserDefaults.standard.set(page.rawValue, forKey: "pendingOpenPageIntent")
            if page == .tasks || page == .schedule {
                UserDefaults.standard.set(page.rawValue, forKey: "pendingOpenPlanTab")
            }
            return .result()
        }
        switch page {
        case .focus:
            dependency.selectedMainTab = .focus
        case .tasks:
            dependency.selectedMainTab = .plan
            dependency.pendingPlanTab = .task
        case .schedule:
            dependency.selectedMainTab = .plan
            dependency.pendingPlanTab = .calendar
        case .habits:
            dependency.selectedMainTab = .habit
        case .stats:
            dependency.selectedMainTab = .stats
        case .settings:
            dependency.selectedMainTab = .settings
        }
        return .result()
    }
}

// MARK: - 快捷指令注册（Siri 短语 / 快捷指令 App 精选）
//
// 说明：所有 AppIntent 均会自动出现在「快捷指令」App 的 FlowTakt 分类中；
// 此处注册的 AppShortcut 额外提供 Siri 短语与精选展示（上限 10 条，当前 9 条）。

struct FlowTaktShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartFocusIntent(),
            phrases: [
                "在 ${applicationName} 中开始专注",
                "用 ${applicationName} 开始一个番茄钟",
            ],
            shortTitle: "开始专注",
            systemImageName: "timer"
        )
        AppShortcut(
            intent: StartBreakIntent(),
            phrases: [
                "用 ${applicationName} 开始休息",
                "在 ${applicationName} 中开始短休息",
            ],
            shortTitle: "开始休息",
            systemImageName: "cup.and.saucer.fill"
        )
        AppShortcut(
            intent: PauseFocusIntent(),
            phrases: [
                "暂停 ${applicationName} 的专注",
                "用 ${applicationName} 暂停专注",
            ],
            shortTitle: "暂停专注",
            systemImageName: "pause.fill"
        )
        AppShortcut(
            intent: ResumeFocusIntent(),
            phrases: [
                "继续 ${applicationName} 的专注",
                "用 ${applicationName} 继续专注",
            ],
            shortTitle: "继续专注",
            systemImageName: "play.fill"
        )
        AppShortcut(
            intent: StopFocusIntent(),
            phrases: [
                "在 ${applicationName} 中停止专注",
                "让 ${applicationName} 结束专注",
            ],
            shortTitle: "停止专注",
            systemImageName: "stop.fill"
        )
        AppShortcut(
            intent: AddTaskIntent(),
            phrases: [
                "用 ${applicationName} 新建任务",
                "在 ${applicationName} 中创建任务",
            ],
            shortTitle: "新建任务",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: CheckInHabitIntent(),
            phrases: [
                "用 ${applicationName} 给习惯打卡",
            ],
            shortTitle: "习惯打卡",
            systemImageName: "checkmark.circle.fill"
        )
        AppShortcut(
            intent: TodayStatsIntent(),
            phrases: [
                "看看 ${applicationName} 今天的专注统计",
                "在 ${applicationName} 中查看今日统计",
            ],
            shortTitle: "今日统计",
            systemImageName: "chart.bar.fill"
        )
        AppShortcut(
            intent: OpenPageIntent(),
            phrases: [
                "打开 ${applicationName} 的 \(\.$page) 页面",
            ],
            shortTitle: "打开页面",
            systemImageName: "arrow.up.forward.app"
        )
    }
}

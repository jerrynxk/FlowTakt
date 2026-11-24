import Foundation
import SwiftUI
import CoreData
import Combine
import BackgroundTasks

// MARK: - 主标签枚举（供 TabView selection 绑定与深链）

enum MainTab: Hashable, CaseIterable {
    case focus
    case plan
    case habit
    case stats
    case settings
}

// MARK: - 依赖注入容器

final class AppDependency: ObservableObject {
    /// 供 AppIntents（快捷指令/Siri）访问运行中的 VM 单例；App 入口初始化时赋值
    static weak var shared: AppDependency?

    // MARK: - 数据层
    let persistenceController: PersistenceController

    // MARK: - 服务层
    let timerManager: TimerManager
    let focusService: FocusServiceProtocol
    let taskService: TaskServiceProtocol
    let achievementService: AchievementServiceProtocol
    let notificationService: NotificationServiceProtocol
    let appBlockerService: AppBlockerServiceProtocol
    let audioService: AudioServiceProtocol
    let speechService: SpeechServiceProtocol
    let syncService: SyncServiceProtocol
    let scheduleService: ScheduleServiceProtocol
    let habitService: HabitServiceProtocol
    let timeRecordService: TimeRecordServiceProtocol
    let reminderService: ReminderServiceProtocol
    let tagService: TagServiceProtocol

    // MARK: - ViewModel 层
    let focusViewModel: FocusViewModel
    let taskViewModel: TaskViewModel
    let statsViewModel: StatsViewModel
    let settingsViewModel: SettingsViewModel
    let achievementViewModel: AchievementViewModel
    let scheduleViewModel: ScheduleViewModel
    let habitViewModel: HabitViewModel
    let timeRecordViewModel: TimeRecordViewModel
    let tagViewModel: TagViewModel

    // MARK: - 导航（深链 / Widget 点击）

    /// 当前选中的主标签，供 MainTabView 的 TabView(selection:) 绑定
    @Published var selectedMainTab: MainTab = {
        // v1.3.4p：dev 工具 — 通过 `simctl launch --setenv INITIAL_TAB=plan` 切换默认 Tab，
        // 用于 iPad 多 Tab 截图测试；生产环境（env 不设置）保持 .focus
        let env = ProcessInfo.processInfo.environment["INITIAL_TAB"] ?? ""
        let envTab = MainTab.allCases.first(where: { tab in
            switch env {
            case "focus":    return tab == .focus
            case "plan":     return tab == .plan
            case "habit":    return tab == .habit
            case "stats":    return tab == .stats
            case "settings": return tab == .settings
            default:         return tab == .focus
            }
        }) ?? .focus
        if env.isEmpty {
            // 修复（2026-10-15 审查 P1-020）：消费 Siri「打开页面」冷启动暂存意图
            // （OpenPageIntent 在 AppDependency 就绪前执行时落盘，此处应用）
            let defaults = UserDefaults.standard
            if let raw = defaults.string(forKey: "pendingOpenPageIntent") {
                defaults.removeObject(forKey: "pendingOpenPageIntent")
                switch raw {
                case "focus":    return .focus
                case "tasks", "schedule": return .plan
                case "habits":   return .habit
                case "stats":    return .stats
                case "settings": return .settings
                default: break
                }
            }
        }
        return envTab
    }()
    /// 计划页内部子标签（task / calendar）的待应用目标；PlanView 消费后置 nil
    @Published var pendingPlanTab: PlanView.PlanTab? = nil

    /// 专注页当前计时模式（false=番茄钟 / true=正计时）。
    /// 修复（2026-11-22 iPad bug）：此状态原为 FocusView 本地 @State，iPad 调整窗口时
    /// horizontalSizeClass 在 regular/compact 边界跳变 → MainTabView 的 Group 在
    /// NavigationSplitView ↔ TabView 间换分支 → FocusView 被整体销毁重建 → @State 归零，
    /// 用户表现「正计时中一调窗口就跳回番茄钟」。提升到跨视图重建存活的 DI 容器后消除该问题。
    /// 冷启动仍默认番茄钟（保持原语义）；仅内存态，不持久化。
    @Published var isStopwatchMode: Bool = false

    init() {
        // 初始化 PersistenceController
        persistenceController = PersistenceController.shared

        // 初始化 TimerManager
        timerManager = TimerManager()

        // 初始化 Service 层
        let notificationService = NotificationService()
        self.notificationService = notificationService
        self.appBlockerService = AppBlockerService()
        self.audioService = AudioService()
        self.speechService = SpeechService()
        self.syncService = SyncService(persistenceController: persistenceController)
        // onError 接线要求具体类型（协议未声明回调），统一"先建局部变量 → 接线 → 赋 self"
        let scheduleService = ScheduleService(persistenceController: persistenceController)
        self.scheduleService = scheduleService
        self.reminderService = ReminderService(persistenceController: persistenceController)
        let habitService = HabitService(persistenceController: persistenceController)
        self.habitService = habitService
        let timeRecordService = TimeRecordService(persistenceController: persistenceController)
        self.timeRecordService = timeRecordService
        // 标签服务（用户反馈 2026-11-19：打通任务↔标签关联，补创建入口）
        let tagService = TagService(persistenceController: persistenceController)
        self.tagService = tagService

        let focusService = FocusService(
            persistenceController: persistenceController,
            notificationService: notificationService
        )
        self.focusService = focusService

        let taskService = TaskService(persistenceController: persistenceController)
        self.taskService = taskService
        // 修复（2026-10-14 P2）：Service 的 `onError` 此前全仓从未赋值 —— 声明了回调却
        // 没有任何接线，save 失败永远只落进 print，调用方（ViewModel/UI）毫不知情。
        // 统一接到日志上报器，保证「失败可被观测」这一契约真正成立。
        focusService.onError = { ServiceErrorReporter.shared.report($0, context: "FocusService") }
        // 修复（2026-10-15 审查 P1-006/P1-007）：onError 接线补全到全部 Service
        // （TaskService 原来因 DI 持协议引用而不可达；Habit/Schedule/TimeRecord 无声明，本轮已补）
        taskService.onError = { ServiceErrorReporter.shared.report($0, context: "TaskService") }
        scheduleService.onError = { ServiceErrorReporter.shared.report($0, context: "ScheduleService") }
        habitService.onError = { ServiceErrorReporter.shared.report($0, context: "HabitService") }
        timeRecordService.onError = { ServiceErrorReporter.shared.report($0, context: "TimeRecordService") }
        tagService.onError = { ServiceErrorReporter.shared.report($0, context: "TagService") }

        let achievementService = AchievementService(
            persistenceController: persistenceController
        )
        // 修复（2026-10-14 P2）：onError 全仓首次真正接线（此前只有声明、没有赋值点）
        achievementService.onError = { ServiceErrorReporter.shared.report($0, context: "AchievementService") }
        self.achievementService = achievementService

        // 初始化 ViewModel 层
        self.focusViewModel = FocusViewModel(
            focusService: focusService,
            timerManager: timerManager,
            notificationService: notificationService,
            appBlockerService: appBlockerService,
            audioService: audioService,
            achievementService: achievementService,
            taskService: taskService,
            speechService: speechService
        )

        self.taskViewModel = TaskViewModel(
            taskService: taskService,
            persistenceController: persistenceController
        )

        self.tagViewModel = TagViewModel(
            tagService: tagService,
            persistenceController: persistenceController
        )

        self.statsViewModel = StatsViewModel(
            focusService: focusService,
            taskService: taskService,
            persistenceController: persistenceController,
            // 用户反馈 2026-11-17：正计时时长计入统计总和
            timeRecordService: timeRecordService
        )

        self.settingsViewModel = SettingsViewModel(syncService: syncService)

        self.achievementViewModel = AchievementViewModel(
            achievementService: achievementService,
            persistenceController: persistenceController
        )

        self.scheduleViewModel = ScheduleViewModel(
            scheduleService: scheduleService,
            persistenceController: persistenceController
        )

        self.habitViewModel = HabitViewModel(
            habitService: habitService,
            persistenceController: persistenceController
        )

        self.timeRecordViewModel = TimeRecordViewModel(
            timeRecordService: timeRecordService,
            persistenceController: persistenceController
        )

        // 注入数据库重置回调（在所有属性初始化后）
        settingsViewModel.onResetDatabase = { [weak self] completion in
            guard let self = self else {
                completion(.failure(PersistenceController.PurgeAbortError.selfDeallocated))
                return
            }
            self.persistenceController.resetDatabase(completion: completion)
        }

        // 注入 iCloud 同步切换回调（2026-10-15 审查 P0-1）：运行时重载 store，
        // 真正挂载/卸载 CloudKit（原实现仅写 UserDefaults，重启前开关不生效）
        settingsViewModel.onCloudSyncChanged = { [weak self] enabled, completion in
            guard let self = self else {
                completion(.failure(PersistenceController.PurgeAbortError.selfDeallocated))
                return
            }
            self.persistenceController.applyCloudKitConfiguration(enabled: enabled, completion: completion)
        }

        // 消费 Siri「打开任务/日程页」冷启动暂存（2026-10-15 审查 P1-020）：
        // selectedMainTab 闭包只负责主 Tab；计划页子 Tab 需在依赖就绪后补投递
        if let raw = UserDefaults.standard.string(forKey: "pendingOpenPlanTab") {
            UserDefaults.standard.removeObject(forKey: "pendingOpenPlanTab")
            pendingPlanTab = (raw == "tasks") ? .task : .calendar
        }

        // 注册单例引用（供 AppIntents 等系统入口访问 VM；须在所有存储属性初始化完成后）
        AppDependency.shared = self

        // 注册专注控制桥（灵动岛/锁屏 Live Activity 按钮与快捷指令的暂停/继续/停止，2026-10-14）
        // FocusControlBridge 定义于 FlowTaktShared（Widget 也编译该文件），
        // 系统在 App 进程内执行按钮 Intent 时经此闭包进入真实 VM。
        //
        // 修复（2026-10-15）：按钮在**背景/冷启动**执行时 FocusView 未上屏 →
        // restorePendingSessionIfNeeded 不执行 → timerState 停留 .idle →
        // pause/resume 的 guard 静默吞掉点击（用户表现为「点了没反应/反应慢」）。
        // 三个入口先做最小状态对齐（ensureOperableStateForExternalControl）再执行控制动作。
        FocusControlBridge.pause = { [weak self] in
            guard let self else { return }
            self.focusViewModel.ensureOperableStateForExternalControl()
            self.focusViewModel.pauseFocus()
        }
        FocusControlBridge.resume = { [weak self] in
            guard let self else { return }
            self.focusViewModel.ensureOperableStateForExternalControl()
            self.focusViewModel.resumeFocus()
        }
        FocusControlBridge.stop = { [weak self] in
            guard let self else { return }
            self.focusViewModel.ensureOperableStateForExternalControl()
            self.focusViewModel.abandonSession()
        }
    }

    /// 应用启动初始化
    /// 审查修复（2026-08-12）：加幂等保护，避免视图重建导致 .task 重复执行
    /// 通知授权 / rescheduleAll / BGTask 注册
    private var hasSetupApp = false
    func setupApp() {
        guard !hasSetupApp else { return }
        hasSetupApp = true
        // 请求通知权限
        Swift.Task {
            _ = await notificationService.requestAuthorization()
            // 权限确定后重排提醒（未授权则仅刷新小组件快照）
            // 崩溃修复（2026-10-02）：`ReminderService` 未标 @MainActor，其
            // `rescheduleWorkItem` 存在并发读改写。`await` 之后 continuation 在
            // Swift 5 非严格模式下不保证回到主线程，故显式 hop 一次。
            await MainActor.run { [reminderService] in
                reminderService.rescheduleAll()
            }
        }
        // 设置 iCloud 同步
        syncService.setupCloudKit()
        // 同步语言偏好到 App Group（首次启动时 App Group 尚无记录，Widget 需与主 App 默认语言一致）
        WidgetDataStore.writeLanguage(L10n.shared.appLanguage)
        // 注意：后台刷新任务的**注册**已移至 `AppDelegate.application(_:didFinishLaunchingWithOptions:)`
        // （Apple 要求注册在该方法返回前完成）。此处只负责排下一次刷新。
        scheduleNextBackgroundRefresh()
    }

    /// BGTask 标识符（注册由 `AppDelegate` 在 `didFinishLaunchingWithOptions` 完成 ——
    /// Apple 要求注册必须发生在该方法返回前；此前在 SwiftUI `.task` 里注册，时点已晚，
    /// `register` 返回 false 且后台刷新静默失效）。
    static let backgroundRefreshIdentifier = "com.flowtakt.FlowTakt.refresh"

    /// 处理一次后台刷新任务（由 `AppDelegate` 的注册 handler 调用）
    func handleBackgroundRefresh(_ task: BGTask) {
        task.expirationHandler = {
            // 修复（P2）：原实现与主流程并发调用 setTaskCompleted（系统只允许一次，
            // 重复调用会抛异常）。用一次性门闩保证只有一条路径完成它。
            Self.backgroundRefreshCompletion.claim(on: task, success: false)
        }
        reminderService.rescheduleAll()
        Self.backgroundRefreshCompletion.claim(on: task, success: true)
        scheduleNextBackgroundRefresh()
    }

    /// 后台任务「一次性完成」门闩（`expirationHandler` 与主流程竞争同一 task）
    private static let backgroundRefreshCompletion = BackgroundRefreshCompletionGate()

    /// BGTask 完成门闩：保证 `setTaskCompleted` 对同一 task 只被调用一次
    final class BackgroundRefreshCompletionGate {
        private var completedTaskIdentifiers = Set<String>()

        func claim(on task: BGTask, success: Bool) {
            let key = task.identifier
            guard !completedTaskIdentifiers.contains(key) else { return }
            completedTaskIdentifiers.insert(key)
            task.setTaskCompleted(success: success)
        }
    }

    /// 调度下一次后台刷新（最早 30 分钟后，避免频繁唤醒）
    func scheduleNextBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "com.flowtakt.FlowTakt.refresh")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("⚠️ BGTaskScheduler 提交失败：\(error.localizedDescription)")
        }
    }

    /// 深链路由：解析 flowtakt:// 各 host 跳转到对应模块。
    /// 支持：schedule（可选 /<id> 定位具体事件）、tasks（可选 /archived）、
    ///       habit、stats、focus、settings
    func handleDeepLink(_ url: URL) {
        guard url.scheme == "flowtakt" else { return }
        switch url.host?.lowercased() {
        case "schedule":
            selectedMainTab = .plan
            pendingPlanTab = .calendar
            if let id = url.pathComponents.dropFirst().first, !id.isEmpty {
                pendingScheduleItemID = id
            }
        case "tasks":
            selectedMainTab = .plan
            pendingPlanTab = .task
            if let seg = url.pathComponents.dropFirst().first, seg == "archived" {
                pendingTaskTab = "archived"
            }
        case "habit":
            selectedMainTab = .habit
        case "stats":
            selectedMainTab = .stats
        case "focus":
            selectedMainTab = .focus
        case "settings":
            selectedMainTab = .settings
        default:
            break
        }
    }

    /// 待定位的日程事件 ID（来自深链 flowtakt://schedule/<id>），ScheduleView 消费后置 nil
    @Published var pendingScheduleItemID: String? = nil
    /// 待应用的任务子标签（"archived" 等），TaskListView 消费后置 nil
    @Published var pendingTaskTab: String? = nil
}

// MARK: - 数据导出（CSV）

/// 导出结果
enum ExportResult {
    /// 成功，携带生成的 CSV 文件 URL 列表
    case success([URL])
    /// 持久化存储未就绪（冷启动 CloudKit 加载慢、或重置数据库进行中）
    case storeNotReady
    /// 库中没有任何可导出的数据
    case noData
    /// 写入文件失败
    case failed(String)
}

/// 按实体各出一份扁平 CSV（任务 / 专注会话 / 习惯打卡），写入临时目录并返回文件 URL，
/// 供系统分享面板打包分享。列名使用英文，日期统一 ISO 8601，便于表格软件与跨平台解析。
enum DataExportService {
    /// 在后台上下文异步导出全部实体，避免主线程同步 fetch 大量数据阻塞 UI。
    /// 导出完成后在主线程回调结果（必须在主线程回调，供 SwiftUI 更新 @State）。
    ///
    /// 修复（2026-10-14，「导出数据提示导出失败」）：原实现硬编码 `PersistenceController.shared`
    /// 且无 store 就绪守卫，冷启动 CloudKit 加载未完成时后台 context 的 fetch 抛错，
    /// 三个导出函数各返回 nil → `urls.isEmpty` → UI 误报「导出失败」。
    /// 现改为：可注入持久化控制器 + 就绪守卫 + 区分「无数据」与「导出失败」两种语义。
    static func exportAll(completion: @escaping (ExportResult) -> Void) {
        exportAll(using: .shared, completion: completion)
    }

    /// 注入持久化控制器的版本（internal 供单元测试验证）。
    static func exportAll(using persistence: PersistenceController,
                          completion: @escaping (ExportResult) -> Void) {
        // store 未就绪时后台 context 的 fetch 会抛 ObjC 异常（Swift 无法捕获）导致崩溃，
        // 必须先短路。参见 PersistenceController.canFetchSafely 的说明。
        guard persistence.canFetchSafely("CSV 数据导出") else {
            DispatchQueue.main.async { completion(.storeNotReady) }
            return
        }

        let bg = persistence.newBackgroundContext()
        bg.perform {
            var urls: [URL] = []
            // 逐实体导出：任一实体无数据只是跳过（不算失败），
            // 全部实体皆无数据才应提示「无数据可导出」而非「导出失败」。
            // 注：直接调用而非存成函数数组 —— 后者会在 bg.perform 的非隔离闭包里
            // 触发 ActorIsolatedCall 警告（这些导出函数是 @MainActor 隔离的）。
            if let u = exportTasks(in: bg) { urls.append(u) }
            if let u = exportFocusSessions(in: bg) { urls.append(u) }
            if let u = exportHabitRecords(in: bg) { urls.append(u) }
            if let u = exportHabits(in: bg) { urls.append(u) }
            if let u = exportTimeRecords(in: bg) { urls.append(u) }
            if let u = exportScheduleItems(in: bg) { urls.append(u) }
            if let u = exportTags(in: bg) { urls.append(u) }

            let result: ExportResult
            if !urls.isEmpty {
                result = .success(urls)
            } else if hasAnyRows(in: bg) {
                // 有数据却一个文件都没写出来 → 真正的写入失败
                result = .failed(L10n.shared.导出失败提示)
            } else {
                result = .noData
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// 可导出实体清单（**单一来源**，修复 P2：原先与 `exportAll` 的 exporters 分列两份，
    /// 新增实体时只改一处会让「有数据却提示无可导出」或反之）。
    /// 导出实现见 `exportAll` —— 两者必须同步，本清单即其权威声明。
    private static let exportableEntities = [
        "Task", "FocusSession", "HabitRecord", "Habit", "TimeRecord", "ScheduleItem", "Tag"
    ]

    private static func hasAnyRows(in ctx: NSManagedObjectContext) -> Bool {
        for entityName in exportableEntities {
            let request = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
            if let count = try? ctx.count(for: request), count > 0 { return true }
        }
        return false
    }

    // MARK: - 任务

    private static func exportTasks(in ctx: NSManagedObjectContext) -> URL? {
        let req = Task.fetchRequest()
        req.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
        guard let items = try? ctx.fetch(req), !items.isEmpty else { return nil }
        let header = ["id", "title", "notes", "priority", "status",
                      "estimatedPomodoros", "completedPomodoros",
                      "dueDate", "completedAt", "createdAt", "updatedAt"]
        let rows = items.map { t -> [String] in
            [csvField(t.id), csvField(t.title), csvField(t.notes),
             csvField(Int(t.priority)), csvField(t.status),
             csvField(Int(t.estimatedPomodoros)), csvField(Int(t.completedPomodoros)),
             csvField(t.dueDate), csvField(t.completedAt),
             csvField(t.createdAt), csvField(t.updatedAt)]
        }
        return writeCSV(filename: "flowtakt_tasks.csv", header: header, rows: rows)
    }

    // MARK: - 专注会话

    private static func exportFocusSessions(in ctx: NSManagedObjectContext) -> URL? {
        let req = FocusSession.fetchRequest()
        req.sortDescriptors = [NSSortDescriptor(key: "startTime", ascending: false)]
        guard let items = try? ctx.fetch(req), !items.isEmpty else { return nil }
        let header = ["id", "startTime", "endTime", "plannedDuration", "actualDuration",
                      "phase", "roundIndex", "status", "earnedPoints", "taskId",
                      "createdAt", "updatedAt"]
        let rows = items.map { s -> [String] in
            [csvField(s.id), csvField(s.startTime), csvField(s.endTime),
             csvField(s.plannedDuration), csvField(s.actualDuration),
             csvField(s.phase), csvField(Int(s.roundIndex)), csvField(s.status),
             csvField(Int(s.earnedPoints)), csvField(s.task?.id),
             csvField(s.createdAt), csvField(s.updatedAt)]
        }
        return writeCSV(filename: "flowtakt_focus_sessions.csv", header: header, rows: rows)
    }

    // MARK: - 习惯打卡

    private static func exportHabitRecords(in ctx: NSManagedObjectContext) -> URL? {
        let req = HabitRecord.fetchRequest()
        req.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        guard let items = try? ctx.fetch(req), !items.isEmpty else { return nil }
        let header = ["id", "habitName", "date", "count", "note", "createdAt"]
        // 崩溃修复（2026-10-02）：`HabitRecord.habit` 为非可选关系，CloudKit 不支持级联删除，
        // 跨设备合并后会残留 `habit == nil` 的孤儿记录。强取 `.name` 会 EXC_BAD_ACCESS，
        // 故改为安全解包，缺失时导出空字符串（保持列对齐）。
        let rows = items.map { r -> [String] in
            [csvField(r.id), csvField(r.habit?.name ?? ""), csvField(r.date),
             csvField(Int(r.count)), csvField(r.note), csvField(r.createdAt)]
        }
        return writeCSV(filename: "flowtakt_habit_records.csv", header: header, rows: rows)
    }

    /// 内部测试入口：直接导出习惯打卡 CSV（供崩溃回归测试验证孤儿记录不崩溃）。
    static func exportHabitRecordsForTesting(in ctx: NSManagedObjectContext) -> URL? {
        return exportHabitRecords(in: ctx)
    }

    // MARK: - 习惯

    /// 补齐（2026-10-14）：原实现只导出 任务/专注会话/习惯打卡 三类实体，
    /// 习惯本身、计时记录、日程、标签全部缺失 —— 只用这些功能的用户点「导出数据」
    /// 会得到空结果（旧实现误报为「导出失败」）。此处补齐至与 JSON 备份一致的 7 类实体。
    private static func exportHabits(in ctx: NSManagedObjectContext) -> URL? {
        let req = Habit.fetchRequest()
        req.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        guard let items = try? ctx.fetch(req), !items.isEmpty else { return nil }
        let header = ["id", "name", "description", "iconName", "colorHex",
                      "frequency", "targetCount", "currentStreak", "longestStreak",
                      "createdAt", "updatedAt"]
        let rows = items.map { h -> [String] in
            [csvField(h.id), csvField(h.name), csvField(h.descriptionText),
             csvField(h.iconName), csvField(h.colorHex), csvField(h.frequency),
             csvField(Int(h.targetCount)), csvField(Int(h.currentStreak)),
             csvField(Int(h.longestStreak)), csvField(h.createdAt), csvField(h.updatedAt)]
        }
        return writeCSV(filename: "flowtakt_habits.csv", header: header, rows: rows)
    }

    // MARK: - 计时记录

    private static func exportTimeRecords(in ctx: NSManagedObjectContext) -> URL? {
        let req = TimeRecord.fetchRequest()
        req.sortDescriptors = [NSSortDescriptor(key: "startTime", ascending: false)]
        guard let items = try? ctx.fetch(req), !items.isEmpty else { return nil }
        let header = ["id", "startTime", "endTime", "duration", "note", "project",
                      "isBillable", "taskId", "tagId", "createdAt", "updatedAt"]
        let rows = items.map { r -> [String] in
            [csvField(r.id), csvField(r.startTime), csvField(r.endTime),
             csvField(r.duration), csvField(r.note), csvField(r.project),
             csvField(r.isBillable), csvField(r.task?.id), csvField(r.tag?.id),
             csvField(r.createdAt), csvField(r.updatedAt)]
        }
        return writeCSV(filename: "flowtakt_time_records.csv", header: header, rows: rows)
    }

    // MARK: - 日程

    private static func exportScheduleItems(in ctx: NSManagedObjectContext) -> URL? {
        let req = ScheduleItem.fetchRequest()
        req.sortDescriptors = [NSSortDescriptor(key: "startDate", ascending: false)]
        guard let items = try? ctx.fetch(req), !items.isEmpty else { return nil }
        let header = ["id", "title", "startDate", "endDate", "isAllDay", "location",
                      "notes", "colorHex", "category", "repeatRule",
                      "reminderEnabled", "reminderLeadMinutes", "taskId", "createdAt", "updatedAt"]
        let rows = items.map { e -> [String] in
            [csvField(e.id), csvField(e.title), csvField(e.startDate), csvField(e.endDate),
             csvField(e.isAllDay), csvField(e.location), csvField(e.notes),
             csvField(e.colorHex), csvField(e.category), csvField(e.repeatRule),
             csvField(e.reminderEnabled), csvField(Int(e.reminderLeadMinutes)),
             csvField(e.task?.id), csvField(e.createdAt), csvField(e.updatedAt)]
        }
        return writeCSV(filename: "flowtakt_schedule_items.csv", header: header, rows: rows)
    }

    // MARK: - 标签

    private static func exportTags(in ctx: NSManagedObjectContext) -> URL? {
        let req = Tag.fetchRequest()
        req.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        guard let items = try? ctx.fetch(req), !items.isEmpty else { return nil }
        let header = ["id", "name", "colorHex", "createdAt"]
        let rows = items.map { t -> [String] in
            [csvField(t.id), csvField(t.name), csvField(t.colorHex), csvField(t.createdAt)]
        }
        return writeCSV(filename: "flowtakt_tags.csv", header: header, rows: rows)
    }

    // MARK: - CSV 写入与转义

    /// CSV 写入（internal 供单元测试验证产出）
    static func writeCSV(filename: String, header: [String], rows: [[String]]) -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(filename)
        var lines = [header.joined(separator: ",")]
        lines.append(contentsOf: rows.map { $0.joined(separator: ",") })
        let content = lines.joined(separator: "\n")
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            print("⚠️ CSV 导出失败：\(error.localizedDescription)")
            return nil
        }
    }

    /// 将任意值转为 CSV 字段字符串，并对含逗号/引号/换行的字段加引号转义（RFC 4180）
    /// CSV 导出日期格式化器（静态缓存，审查 #11：避免每行创建）
    private static let csvDateFormatter = ISO8601DateFormatter()

    /// CSV 字段转义（internal 供单元测试验证 RFC 4180）
    static func csvField(_ value: Any?) -> String {
        guard let value else { return "" }
        let raw: String
        if let date = value as? Date {
            raw = Self.csvDateFormatter.string(from: date)
        } else if let uuid = value as? UUID {
            raw = uuid.uuidString
        } else {
            raw = "\(value)"
        }
        // 修复（2026-10-14 审查 P2-8）：防 CSV 公式注入 ——
        // 以 = + - @ 开头的字段在 Excel / Numbers 打开时会被当公式执行（=cmd|... 经典攻击向量）。
        // 统一加前导单引号强制为文本。
        let needsQuote = raw.contains(",") || raw.contains("\"") || raw.contains("\n")
            || raw.contains("\r") || startsWithFormulaTrigger(raw)
        if needsQuote {
            let escaped = raw.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return raw
    }

    /// 是否以公式触发字符开头（CSV Injection 防护判据，收口在此一处）
    private static func startsWithFormulaTrigger(_ raw: String) -> Bool {
        guard let first = raw.first else { return false }
        return first == "=" || first == "+" || first == "-" || first == "@"
    }
}

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

    // MARK: - ViewModel 层
    let focusViewModel: FocusViewModel
    let taskViewModel: TaskViewModel
    let statsViewModel: StatsViewModel
    let settingsViewModel: SettingsViewModel
    let achievementViewModel: AchievementViewModel
    let scheduleViewModel: ScheduleViewModel
    let habitViewModel: HabitViewModel
    let timeRecordViewModel: TimeRecordViewModel

    // MARK: - 导航（深链 / Widget 点击）

    /// 当前选中的主标签，供 MainTabView 的 TabView(selection:) 绑定
    @Published var selectedMainTab: MainTab = {
        // v1.3.4p：dev 工具 — 通过 `simctl launch --setenv INITIAL_TAB=plan` 切换默认 Tab，
        // 用于 iPad 多 Tab 截图测试；生产环境（env 不设置）保持 .focus
        let env = ProcessInfo.processInfo.environment["INITIAL_TAB"] ?? ""
        return MainTab.allCases.first(where: { tab in
            switch env {
            case "focus":    return tab == .focus
            case "plan":     return tab == .plan
            case "habit":    return tab == .habit
            case "stats":    return tab == .stats
            case "settings": return tab == .settings
            default:         return tab == .focus
            }
        }) ?? .focus
    }()
    /// 计划页内部子标签（task / calendar）的待应用目标；PlanView 消费后置 nil
    @Published var pendingPlanTab: PlanView.PlanTab? = nil

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
        self.scheduleService = ScheduleService(persistenceController: persistenceController)
        self.reminderService = ReminderService(persistenceController: persistenceController)
        self.habitService = HabitService(persistenceController: persistenceController)
        self.timeRecordService = TimeRecordService(persistenceController: persistenceController)

        let focusService = FocusService(
            persistenceController: persistenceController,
            notificationService: notificationService
        )
        self.focusService = focusService

        self.taskService = TaskService(persistenceController: persistenceController)

        let achievementService = AchievementService(
            persistenceController: persistenceController
        )
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

        self.statsViewModel = StatsViewModel(
            focusService: focusService,
            taskService: taskService,
            persistenceController: persistenceController
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
            guard let self = self else { completion(false); return }
            self.persistenceController.resetDatabase(completion: completion)
        }

        // 注册单例引用（供 AppIntents 等系统入口访问 VM；须在所有存储属性初始化完成后）
        AppDependency.shared = self
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
        // 注册后台刷新任务（系统定期唤醒 App 刷新小组件快照）
        registerBackgroundRefresh()
    }

    /// 注册 BGTaskScheduler 后台应用刷新任务。
    /// 需要 Info.plist 中声明 UIBackgroundModes = [fetch] 且配置
    /// BGTaskSchedulerPermittedIdentifiers = com.flowtakt.FlowTakt.refresh，
    /// App 才会出现在系统「设置 → 通用 → 后台应用刷新」列表中。
    private func registerBackgroundRefresh() {
        let identifier = "com.flowtakt.FlowTakt.refresh"
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { [weak self] task in
            // 处理任务：刷新提醒数据 + 小组件快照
            task.expirationHandler = { task.setTaskCompleted(success: false) }
            self?.reminderService.rescheduleAll()
            // 完成并调度下一次刷新
            task.setTaskCompleted(success: true)
            self?.scheduleNextBackgroundRefresh()
        }
        scheduleNextBackgroundRefresh()
    }

    /// 调度下一次后台刷新（最早 30 分钟后，避免频繁唤醒）
    private func scheduleNextBackgroundRefresh() {
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

/// 按实体各出一份扁平 CSV（任务 / 专注会话 / 习惯打卡），写入临时目录并返回文件 URL，
/// 供系统分享面板打包分享。列名使用英文，日期统一 ISO 8601，便于表格软件与跨平台解析。
enum DataExportService {
    /// 在后台上下文异步导出全部实体，避免主线程同步 fetch 大量数据阻塞 UI。
    /// 导出完成后在主线程回调生成的 CSV 文件 URL 列表（空数组表示无数据）。
    static func exportAll(completion: @escaping ([URL]) -> Void) {
        let bg = PersistenceController.shared.newBackgroundContext()
        bg.perform {
            var urls: [URL] = []
            if let u = exportTasks(in: bg) { urls.append(u) }
            if let u = exportFocusSessions(in: bg) { urls.append(u) }
            if let u = exportHabitRecords(in: bg) { urls.append(u) }
            DispatchQueue.main.async { completion(urls) }
        }
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
        if raw.contains(",") || raw.contains("\"") || raw.contains("\n") {
            return "\"\(raw.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return raw
    }
}

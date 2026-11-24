import Foundation
import CoreData

// MARK: - 备份数据模型（B4，Codable DTO，不直接编码 NSManagedObject）

struct BackupPayload: Codable {
    let version: Int
    let exportedAt: Date
    let tasks: [TaskDTO]
    let focusSessions: [FocusSessionDTO]
    let habits: [HabitDTO]
    let habitRecords: [HabitRecordDTO]
    let timeRecords: [TimeRecordDTO]
    let scheduleItems: [ScheduleItemDTO]
    /// 可选：v1 旧备份无此字段，decode 容错（审查 #5 兼容性）
    let tags: [TagDTO]?

    static let currentVersion = 1
}

struct TagDTO: Codable {
    let id: UUID
    let name: String
    let colorHex: String?
    let createdAt: Date
}

struct TaskDTO: Codable {
    let id: UUID
    let title: String
    let notes: String?
    let status: String
    let estimatedPomodoros: Int16
    let completedPomodoros: Int16
    let priority: Int16
    let dueDate: Date?
    let recurrenceRule: String?
    let recurrenceEndDate: Date?
    let displayOrder: Int16
    let createdAt: Date
    let updatedAt: Date
    let completedAt: Date?
    let estimatedDuration: Double
    let startDate: Date?
    let isRecurring: Bool
    let parentTaskID: UUID?
    let tagIDs: [UUID]
}

struct FocusSessionDTO: Codable {
    let id: UUID
    let startTime: Date
    let endTime: Date?
    let plannedDuration: Double
    let actualDuration: Double
    let phase: String
    let roundIndex: Int16
    let status: String
    let earnedPoints: Int16
    let interruptionReason: String?
    let createdAt: Date
    let updatedAt: Date
    let taskID: UUID?
    let tagID: UUID?
}

struct HabitDTO: Codable {
    let id: UUID
    let name: String
    let descriptionText: String?
    let iconName: String?
    let colorHex: String?
    let frequency: String
    let targetCount: Int16
    let currentStreak: Int16
    let longestStreak: Int16
    let createdAt: Date
    let updatedAt: Date
}

struct HabitRecordDTO: Codable {
    let id: UUID
    let date: Date
    let count: Int16
    let note: String?
    let habitID: UUID
    let createdAt: Date
}

struct TimeRecordDTO: Codable {
    let id: UUID
    let startTime: Date
    let endTime: Date?
    let duration: Double
    let note: String?
    let project: String?
    let isBillable: Bool
    let createdAt: Date
    let updatedAt: Date
}

struct ScheduleItemDTO: Codable {
    let id: UUID
    let title: String
    let startDate: Date
    let endDate: Date?
    let isAllDay: Bool
    let location: String?
    let notes: String?
    let colorHex: String?
    let category: String
    let repeatRule: String?
    let reminderEnabled: Bool
    let reminderLeadMinutes: Int32
    let createdAt: Date
    let updatedAt: Date
}

// MARK: - 备份服务（B4）

// MARK: - DTO 实体初始化器（供导出 map 使用）

@MainActor
extension TaskDTO {
    init(_ task: Task) {
        self.init(id: task.id, title: task.title, notes: task.notes, status: task.status,
                  estimatedPomodoros: task.estimatedPomodoros, completedPomodoros: task.completedPomodoros,
                  priority: task.priority, dueDate: task.dueDate, recurrenceRule: task.recurrenceRule,
                  recurrenceEndDate: task.recurrenceEndDate, displayOrder: task.displayOrder,
                  createdAt: task.createdAt, updatedAt: task.updatedAt, completedAt: task.completedAt,
                  estimatedDuration: task.estimatedDuration, startDate: task.startDate,
                  isRecurring: task.isRecurring, parentTaskID: task.parentTask?.id,
                  tagIDs: task.tags.map(\.id))
    }
}

@MainActor
extension TagDTO {
    init(_ tag: Tag) {
        self.init(id: tag.id, name: tag.name, colorHex: tag.colorHex, createdAt: tag.createdAt)
    }
}

@MainActor
extension FocusSessionDTO {
    init(_ session: FocusSession) {
        self.init(id: session.id, startTime: session.startTime, endTime: session.endTime,
                  plannedDuration: session.plannedDuration, actualDuration: session.actualDuration,
                  phase: session.phase, roundIndex: session.roundIndex, status: session.status,
                  earnedPoints: session.earnedPoints, interruptionReason: session.interruptionReason,
                  createdAt: session.createdAt, updatedAt: session.updatedAt, taskID: session.task?.id,
                  tagID: session.tag?.id)
    }
}

@MainActor
extension HabitDTO {
    init(_ habit: Habit) {
        self.init(id: habit.id, name: habit.name, descriptionText: habit.descriptionText,
                  iconName: habit.iconName, colorHex: habit.colorHex, frequency: habit.frequency,
                  targetCount: habit.targetCount, currentStreak: habit.currentStreak,
                  longestStreak: habit.longestStreak, createdAt: habit.createdAt, updatedAt: habit.updatedAt)
    }
}

@MainActor
extension HabitRecordDTO {
    /// 孤儿记录（`habit` 关系为 nil）无法映射为有效 DTO，返回 nil 由调用方 compactMap 过滤。
    ///
    /// 崩溃修复（2026-10-02）：`HabitRecord.habit` 是数据模型中唯一的非可选关系
    /// （`optional="NO"`，Swift 侧为非可选 `Habit`）。由于
    /// `NSPersistentCloudKitContainer` **不支持级联删除**，另一设备删除 Habit 后
    /// 对应的 HabitRecord 的 CKRecord 会残留在 CloudKit，合并后本地即产生
    /// `habit == nil` 的孤儿记录。原实现直接 `record.habit.id` 强解包会触发
    /// `EXC_BAD_ACCESS`（Unexpectedly found nil）。
    init?(_ record: HabitRecord) {
        guard let habit = record.habit else { return nil }
        self.init(id: record.id, date: record.date, count: record.count, note: record.note,
                  habitID: habit.id, createdAt: record.createdAt)
    }
}

@MainActor
extension TimeRecordDTO {
    init(_ record: TimeRecord) {
        self.init(id: record.id, startTime: record.startTime, endTime: record.endTime,
                  duration: record.duration, note: record.note, project: record.project,
                  isBillable: record.isBillable, createdAt: record.createdAt, updatedAt: record.updatedAt)
    }
}

@MainActor
extension ScheduleItemDTO {
    init(_ event: ScheduleItem) {
        self.init(id: event.id, title: event.title, startDate: event.startDate, endDate: event.endDate,
                  isAllDay: event.isAllDay, location: event.location, notes: event.notes,
                  colorHex: event.colorHex, category: event.category, repeatRule: event.repeatRule,
                  reminderEnabled: event.reminderEnabled, reminderLeadMinutes: event.reminderLeadMinutes,
                  createdAt: event.createdAt, updatedAt: event.updatedAt)
    }
}

/// 全量 JSON 备份/恢复。导出不依赖任何外部文件，恢复前清空现有数据（覆盖式恢复）。
@MainActor
final class BackupService {

    private let persistenceController: PersistenceController

    init(persistenceController: PersistenceController) {
        self.persistenceController = persistenceController
    }

    private var context: NSManagedObjectContext {
        persistenceController.viewContext
    }

    // MARK: - 导出

    /// 导出全量数据为 JSON 文件（**后台上下文执行，不阻塞 UI**），完成后主线程回调文件 URL。
    ///
    /// 修复（2026-10-15）：旧实现整段在主线程同步执行（全表 fetch → DTO 映射 → 编码 →
    /// 写盘），数据量增长后会加成「点击备份 → 分享面板出现」之间的卡顿。
    /// 现与 `DataExportService.exportAll`（CSV 导出）**逐字同构**：重活在
    /// `bg.perform` 中完成、`DispatchQueue.main.async` 回调 —— 该形态也是本模块
    /// 通过并发隔离检查（0 warning）的既有后台导出模式。
    ///
    /// - Parameter completion: 主线程回调；成功携带文件 URL，失败为 nil。
    func exportJSON(completion: @escaping (URL?) -> Void) {
        // store 未就绪时 fetch 抛 ObjC 异常（Swift 无法捕获）→ 先短路
        guard persistenceController.canFetchSafely("JSON 备份导出") else {
            DispatchQueue.main.async { completion(nil) }
            return
        }

        let bg = persistenceController.newBackgroundContext()
        bg.perform {
            let url = BackupExporter.makeBackupFile(in: bg)
            DispatchQueue.main.async { completion(url) }
        }
    }

    /// 从 JSON 文件恢复（覆盖式：先清空现有数据再导入）
    func importJSON(from url: URL) -> Bool {
        // 记录是否已发过 willReset：失败路径据此决定要不要补发 didReset 让 VM 回显数据
        var didPostWillReset = false
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let payload = try decoder.decode(BackupPayload.self, from: data)
            guard payload.version <= BackupPayload.currentVersion else {
                print("⚠️ 备份版本过新：\(payload.version)")
                return false
            }

            // 原子性保障（审查 #1 / 2026-10-14 P0-1）：清空数据【之前】先校验 id 唯一性，
            // 避免 Dictionary(uniqueKeysWithValues:) 对重复 id 触发 fatalError 且数据已清空。
            // 修复（2026-10-14 P2-10）：原先只校验 4 类，补齐 habitRecords / timeRecords /
            // scheduleItems，与 importJSON 内所有 Dictionary 构建点保持一致。
            guard hasUniqueIDs(payload.tasks.map(\.id)),
                  hasUniqueIDs(payload.habits.map(\.id)),
                  hasUniqueIDs(payload.focusSessions.map(\.id)),
                  hasUniqueIDs(payload.habitRecords.map(\.id)),
                  hasUniqueIDs(payload.timeRecords.map(\.id)),
                  hasUniqueIDs(payload.scheduleItems.map(\.id)),
                  hasUniqueIDs(payload.tags?.map(\.id) ?? []) else {
                print("⚠️ 备份包含重复 ID，已拒绝恢复（数据未被改动）")
                return false
            }

            // 空载荷防护（2026-10-14 P2-12）：结构合法但内容全空的 JSON（例如导出了空库、
            // 或文件被截断成 `{}` 的合法变体）会把本地库清空并提示「恢复成功」，
            // 用户数据被无声抹除。空备份一律拒绝。
            if payload.tasks.isEmpty && payload.habits.isEmpty && payload.focusSessions.isEmpty
                && payload.habitRecords.isEmpty && payload.timeRecords.isEmpty
                && payload.scheduleItems.isEmpty && (payload.tags ?? []).isEmpty {
                print("⚠️ 备份内容为空，已拒绝恢复（数据未被改动）")
                return false
            }

            // 崩溃修复（2026-10-02）：清空数据【之前】校验时长类 Double 字段。
            // Int16 字段越界会被 JSONDecoder 抛错并被外层 catch 兜住，但 Double 字段接受
            // 任意有限值 —— `"duration": 1e300` 可合法解码入库，随后在
            // FocusSession+Extensions / TimeRecord+Extensions / StatsView 的 `Int(duration)`
            // 处触发 `Fatal error: Double value cannot be converted to Int`。
            // 崩溃发生在恢复【之后】，用户已损失原数据，故必须前置拦截。
            let invalidDuration = payload.focusSessions.contains { !isDurationSane($0.actualDuration) || !$0.plannedDuration.isSaneValue }
                || payload.timeRecords.contains { !isDurationSane($0.duration) }
            if invalidDuration {
                print("⚠️ 备份包含超出合理范围的时长数据，已拒绝恢复（数据未被改动）")
                return false
            }

            // 覆盖式恢复：清空现有数据（含 Achievement，避免旧成就状态残留）
            // 审查修复（2026-08-12）：先发 databaseWillReset 让各 VM 清空持有的
            // NSManagedObject 引用，避免 UI 访问失效对象触发 "CoreData could not fulfill a fault"
            didPostWillReset = true
            NotificationCenter.default.post(name: .databaseWillReset, object: nil)
            try clearAllData()

            // 重建：先建 Task/Tag（供关联引用），再建依赖关系
            let habitByID = Dictionary(payload.habits.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

            var insertedTasks: [UUID: Task] = [:]
            for dto in payload.tasks {
                let t = Task(context: context)
                t.storageId = dto.id
                t.title = dto.title
                t.notes = dto.notes
                t.status = dto.status
                t.estimatedPomodoros = dto.estimatedPomodoros
                t.completedPomodoros = dto.completedPomodoros
                t.priority = dto.priority
                t.dueDate = dto.dueDate
                t.recurrenceRule = dto.recurrenceRule
                t.recurrenceEndDate = dto.recurrenceEndDate
                t.displayOrder = dto.displayOrder
                t.createdAt = dto.createdAt
                t.updatedAt = dto.updatedAt
                t.completedAt = dto.completedAt
                t.estimatedDuration = dto.estimatedDuration
                t.startDate = dto.startDate
                t.isRecurring = dto.isRecurring
                insertedTasks[dto.id] = t
            }

            var insertedTags: [UUID: Tag] = [:]
            for dto in payload.tags ?? [] {
                let tag = Tag(context: context)
                tag.storageId = dto.id
                tag.name = dto.name
                tag.colorHex = dto.colorHex
                tag.createdAt = dto.createdAt
                insertedTags[dto.id] = tag
            }

            // 二次 pass：任务标签 / 父任务关系
            for dto in payload.tasks {
                guard let task = insertedTasks[dto.id] else { continue }
                task.tags = Set(dto.tagIDs.compactMap { insertedTags[$0] })
                if let parentID = dto.parentTaskID {
                    task.parentTask = insertedTasks[parentID]
                }
            }

            for dto in payload.focusSessions {
                let s = FocusSession(context: context)
                s.storageId = dto.id
                s.startTime = dto.startTime
                s.endTime = dto.endTime
                s.plannedDuration = dto.plannedDuration
                s.actualDuration = dto.actualDuration
                s.phase = dto.phase
                s.roundIndex = dto.roundIndex
                s.status = dto.status
                s.earnedPoints = dto.earnedPoints
                s.interruptionReason = dto.interruptionReason
                s.createdAt = dto.createdAt
                s.updatedAt = dto.updatedAt
                if let taskID = dto.taskID { s.task = insertedTasks[taskID] }
                if let tagID = dto.tagID { s.tag = insertedTags[tagID] }
            }

            var insertedHabits: [UUID: Habit] = [:]
            for dto in payload.habits {
                let h = Habit(context: context)
                h.storageId = dto.id
                h.name = dto.name
                h.descriptionText = dto.descriptionText
                h.iconName = dto.iconName
                h.colorHex = dto.colorHex
                h.frequency = dto.frequency
                h.targetCount = dto.targetCount
                h.currentStreak = dto.currentStreak
                h.longestStreak = dto.longestStreak
                h.createdAt = dto.createdAt
                h.updatedAt = dto.updatedAt
                insertedHabits[dto.id] = h
            }

            for dto in payload.habitRecords {
                guard let habit = insertedHabits[dto.habitID] ?? (habitByID[dto.habitID].map(placeholderHabit(for:))) else {
                    continue   // 引用的习惯缺失（且无 DTO 兜底）→ 跳过该记录
                }
                let r = HabitRecord(context: context)
                r.storageId = dto.id
                r.date = dto.date
                r.count = dto.count
                r.note = dto.note
                r.habit = habit
                r.createdAt = dto.createdAt
            }

            for dto in payload.timeRecords {
                let tr = TimeRecord(context: context)
                tr.storageId = dto.id
                tr.startTime = dto.startTime
                tr.endTime = dto.endTime
                tr.duration = dto.duration
                tr.note = dto.note
                tr.project = dto.project
                tr.isBillable = dto.isBillable
                tr.createdAt = dto.createdAt
                tr.updatedAt = dto.updatedAt
            }

            for dto in payload.scheduleItems {
                let e = ScheduleItem(context: context)
                e.storageId = dto.id
                e.title = dto.title
                e.startDate = dto.startDate
                e.endDate = dto.endDate
                e.isAllDay = dto.isAllDay
                e.location = dto.location
                e.notes = dto.notes
                e.colorHex = dto.colorHex
                e.category = dto.category
                e.repeatRule = dto.repeatRule
                e.reminderEnabled = dto.reminderEnabled
                e.reminderLeadMinutes = dto.reminderLeadMinutes
                e.createdAt = dto.createdAt
                e.updatedAt = dto.updatedAt
            }

            let ok = persistenceController.save()
            guard ok else {
                // 保存失败：删除与插入都在同一事务内，rollback 可完整回退到恢复前的数据
                context.rollback()
                print("⚠️ 备份恢复保存失败，已回滚")
                // 修复（2026-10-14 审查 P1-2）：失败路径也必须发 databaseDidReset ——
                // 各 VM 在 willReset 时已清空数据，不通知将停留在空白界面。
                NotificationCenter.default.post(name: .databaseDidReset, object: nil)
                return false
            }
            // 成功后无需 context.reset()：删除与插入已在同一次 save 中落盘，
            // 且 willReset 已让各 VM 释放旧对象引用（reset 反而会丢弃刚插入对象的缓存）。
            // 审查修复（2026-08-12）：恢复完成，通知各 VM 重新加载数据
            NotificationCenter.default.post(name: .databaseDidReset, object: nil)
            return true
        } catch {
            context.rollback()
            print("⚠️ 备份恢复失败：\(error.localizedDescription)")
            if didPostWillReset {
                NotificationCenter.default.post(name: .databaseDidReset, object: nil)
            }
            return false
        }
    }

    /// 校验 id 数组无重复（恢复前置检查）
    private func hasUniqueIDs(_ ids: [UUID]) -> Bool {
        Set(ids).count == ids.count
    }

    /// 时长字段的合理上限：365 天（秒）。既覆盖任何真实使用场景，
    /// 又远低于 Int64.max，确保后续 `Int(duration)` 转换永不 trap。
    private static let maxSaneDuration: Double = 365 * 24 * 60 * 60

    /// 判断时长是否为有限值且在合理区间内（含负值检查）。
    private func isDurationSane(_ value: Double) -> Bool {
        value.isSaneValue
    }
    // MARK: - 私有

    /// 清空全部业务数据：**仅在上下文中标记删除，不立即保存**。
    ///
    /// 修复（2026-10-14 审查 P0-1）：旧实现按 store 类型分流，SQLite 走
    /// `NSBatchDeleteRequest`。batch 删除**绕过 NSManagedObjectContext、直接写入持久化
    /// 存储**（执行即落盘），因此旧数据在 `clearAllData()` 返回时已不可逆消失；此后
    /// 新数据的 `save()` 一旦失败，`rollback()` 只能丢弃新插入的对象 —— 用户全部数据
    /// 丢失，界面却只提示「恢复失败」。
    /// 现改为逐个 `context.delete`，让「删除旧数据 + 插入新数据」参与**同一次 save()**，
    /// 失败时一次 rollback 即可完整回退。
    private func clearAllData() throws {
        // 含 Achievement：恢复后旧成就状态会与数据不一致，一并清空（AchievementService 会自动重建默认集）
        for entity in ["Task", "FocusSession", "Habit", "HabitRecord", "TimeRecord", "ScheduleItem", "Tag", "Achievement"] {
            let request = NSFetchRequest<NSManagedObject>(entityName: entity)
            // 任一实体清理失败即抛出：交由外层 catch 回滚，绝不留下「删了一半」的库
            for object in try context.fetch(request) {
                context.delete(object)
            }
        }
    }

    /// 当习惯记录引用的习惯缺失时，创建一个占位习惯（恢复完整性）
    private func placeholderHabit(for dto: HabitDTO) -> Habit {
        let h = Habit(context: context)
        h.storageId = dto.id
        h.name = dto.name
        h.frequency = dto.frequency
        h.targetCount = dto.targetCount
        h.createdAt = Date()
        h.updatedAt = Date()
        return h
    }
}

// MARK: - 备份文件后台构建器

/// 构建全量快照并写入临时 JSON 文件（在后台 context 队列执行）。
///
/// 与 `DataExportService` 同型：**文件级、无显式隔离标注**（随模块默认隔离推断）。
/// `BackupService.exportJSON` 在 `bg.perform` 闭包中直接调用本类型方法 —— 这是本模块
/// 既有的后台导出模式（0 warning）。
///
/// 注意：等效逻辑若放入显式 `@MainActor` 标注的类中，会因调用点隔离检查更严格而
/// 触发 `#ActorIsolatedCall` 警告（2026-10-15 实测），故保持独立文件级类型。
private enum BackupExporter {

    /// 构建全量快照并写入临时 JSON 文件；失败返回 nil。
    static func makeBackupFile(in context: NSManagedObjectContext) -> URL? {
        // 只拉取一次，避免逐实体重复扫描（审查 #9）
        let tasks = (try? context.fetch(Task.fetchRequest())) ?? []
        let focusSessions = (try? context.fetch(FocusSession.fetchRequest())) ?? []
        let habits = (try? context.fetch(Habit.fetchRequest())) ?? []
        let habitRecords = (try? context.fetch(HabitRecord.fetchRequest())) ?? []
        let timeRecords = (try? context.fetch(TimeRecord.fetchRequest())) ?? []
        let scheduleItems = (try? context.fetch(ScheduleItem.fetchRequest())) ?? []
        let tags = (try? context.fetch(Tag.fetchRequest())) ?? []

        let payload = BackupPayload(
            version: BackupPayload.currentVersion,
            exportedAt: Date(),
            tasks: tasks.map(TaskDTO.init),
            focusSessions: focusSessions.map(FocusSessionDTO.init),
            habits: habits.map(HabitDTO.init),
            // 崩溃修复（2026-10-02）：compactMap 过滤掉 habit 关系为 nil 的孤儿记录
            // （`HabitRecordDTO.init?` 对 habit == nil 返回 nil），避免强解包触发
            // EXC_BAD_ACCESS。孤儿记录本身已无关联习惯，丢弃不影响有效数据。
            habitRecords: habitRecords.compactMap(HabitRecordDTO.init),
            timeRecords: timeRecords.map(TimeRecordDTO.init),
            scheduleItems: scheduleItems.map(ScheduleItemDTO.init),
            tags: tags.map(TagDTO.init)
        )
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(payload)

            let filename = "FlowTakt_Backup_\(backupDateFormatter.string(from: Date())).json"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            print("⚠️ 备份导出失败：\(error.localizedDescription)")
            return nil
        }
    }

    private static let backupDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmm"
        return f
    }()
}

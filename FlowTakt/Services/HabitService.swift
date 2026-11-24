import Foundation
import CoreData

// MARK: - HabitService 协议

protocol HabitServiceProtocol {
    func createHabit(name: String, descriptionText: String?, iconName: String?, colorHex: String?, frequency: String, targetCount: Int16) -> Habit
    func updateHabit(_ habit: Habit, name: String?, descriptionText: String?, iconName: String?, colorHex: String?, frequency: String?, targetCount: Int16?)
    func deleteHabit(_ habit: Habit)
    func checkIn(habit: Habit, count: Int16, note: String?) -> HabitRecord
    func removeCheckIn(_ record: HabitRecord)
    func fetchAllHabits() -> [Habit]
    func fetchHabitRecords(habit: Habit, from date: Date, to endDate: Date) -> [HabitRecord]
    /// 按日期区间拉取全部习惯的打卡记录（热力图聚合用，跨习惯）
    func fetchRecords(from startDate: Date, to endDate: Date) -> [HabitRecord]
    func recalculateStreak(for habit: Habit)
}

// MARK: - 习惯频率判据收口（2026-10-15 审查 P2-S4）
// "daily"/"weekly"/"monthly" 此前以裸字符串散落在 Service/ViewModel/View 三层，
// 统一以本 enum 的 rawValue 为唯一真值源（CoreData 存库字符串不变，无迁移成本）。

enum HabitFrequency: String {
    case daily
    case weekly
    case monthly
}

// MARK: - 习惯服务实现

@MainActor
final class HabitService: HabitServiceProtocol {
    private let persistenceController: PersistenceController

    /// 错误回调：供 ViewModel 层监听 Service 内部错误（2026-10-15 审查 P1-007 接线）
    var onError: ((Error) -> Void)?

    private var viewContext: NSManagedObjectContext {
        persistenceController.viewContext
    }
    /// save 失败统一上报（判据收口，2026-10-15 审查 P1-001）：
    /// 所有写路径经此检查，store 未就绪/保存失败时不再静默丢弃。
    func saveAndReport() {
        if !persistenceController.save() {
            onError?(AppError.coreDataSaveFailed(NSError(domain: "FlowTakt.HabitService",
                                                         code: NSFileWriteUnknownError)))
        }
    }

    init(persistenceController: PersistenceController) {
        self.persistenceController = persistenceController
    }

    func createHabit(
        name: String,
        descriptionText: String?,
        iconName: String?,
        colorHex: String?,
        frequency: String,
        targetCount: Int16
    ) -> Habit {
        let habit = Habit(context: viewContext)
        habit.storageId = UUID()
        habit.name = name
        habit.descriptionText = descriptionText
        habit.iconName = iconName
        habit.colorHex = colorHex
        habit.frequency = frequency
        habit.targetCount = targetCount
        habit.currentStreak = 0
        habit.longestStreak = 0
        habit.createdAt = Date()
        habit.updatedAt = Date()
        saveAndReport()
        return habit
    }

    func updateHabit(
        _ habit: Habit,
        name: String? = nil,
        descriptionText: String? = nil,
        iconName: String? = nil,
        colorHex: String? = nil,
        frequency: String? = nil,
        targetCount: Int16? = nil
    ) {
        if let name = name { habit.name = name }
        if let descriptionText = descriptionText { habit.descriptionText = descriptionText }
        if let iconName = iconName { habit.iconName = iconName }
        if let colorHex = colorHex { habit.colorHex = colorHex }
        if let frequency = frequency { habit.frequency = frequency }
        if let targetCount = targetCount { habit.targetCount = targetCount }
        habit.updatedAt = Date()
        saveAndReport()
    }

    /// 删除习惯并级联删除其全部打卡记录。
    ///
    /// 崩溃修复（2026-10-02）：原实现仅 `viewContext.delete(habit)`，依赖数据模型中
    /// `Habit.records` 的 `deletionRule="Cascade"`。但 `NSPersistentCloudKitContainer`
    /// **不支持级联删除** —— 设备 A 删除 Habit 时，CloudKit 侧只删除 Habit 的 CKRecord，
    /// 对应 HabitRecord 的 CKRecord 会残留。其他设备同步后即产生 `habit == nil` 的孤儿记录，
    /// 在导出（CSV / JSON 备份）等读取点会触发 `EXC_BAD_ACCESS`。
    ///
    /// 显式删除 records 可让删除集本身参与 CloudKit 同步，从源头消除孤儿记录。
    func deleteHabit(_ habit: Habit) {
        // `Habit.records` 在模型中是 optional="YES" 的 to-many 关系，
        // 但 Swift 侧生成为非可选 Set（CoreData 对 to-many 关系的既定行为）。
        for record in habit.records where !record.isDeleted {
            viewContext.delete(record)
        }
        viewContext.delete(habit)
        saveAndReport()
    }

    @discardableResult
    func checkIn(habit: Habit, count: Int16, note: String?) -> HabitRecord {
        let record = HabitRecord(context: viewContext)
        record.storageId = UUID()
        record.date = Date()
        record.count = count
        record.note = note
        record.createdAt = Date()
        record.habit = habit
        saveAndReport()
        recalculateStreak(for: habit)
        return record
    }

    func removeCheckIn(_ record: HabitRecord) {
        // 防御失效对象访问：已删除或已脱离上下文的记录解引用会触发 CoreData fault
        //（NSObjectInaccessibleException）。
        // 注：`HabitRecord.habit` 现为可选关系（崩溃修复 2026-10-02，因 CloudKit 不支持级联删除，
        // 合并后可能残留 habit == nil 的孤儿记录），故 `habit` 取到 nil 时跳过 streak 重算。
        guard !record.isDeleted, record.managedObjectContext != nil else { return }
        let habit = record.habit
        viewContext.delete(record)
        saveAndReport()
        if let habit {
            recalculateStreak(for: habit)
        }
    }

    func fetchAllHabits() -> [Habit] {
        guard persistenceController.canFetchSafely("HabitService.fetchAllHabits") else { return [] }
        let request = Habit.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Habit.createdAt, ascending: false)]
        do {
            return try viewContext.fetch(request)
        } catch {
            print("获取习惯列表失败：\(error.localizedDescription)")
            return []
        }
    }

    func fetchHabitRecords(habit: Habit, from date: Date, to endDate: Date) -> [HabitRecord] {
        guard persistenceController.canFetchSafely("HabitService.fetchHabitRecords") else { return [] }
        let request = HabitRecord.fetchRequest()
        // 半开区间 [date, endDate)
        request.predicate = NSPredicate(
            format: "habit == %@ AND date >= %@ AND date < %@",
            habit,
            date as NSDate,
            endDate as NSDate
        )
        request.sortDescriptors = [NSSortDescriptor(keyPath: \HabitRecord.date, ascending: false)]
        do {
            return try viewContext.fetch(request)
        } catch {
            print("获取打卡记录失败：\(error.localizedDescription)")
            return []
        }
    }

    func fetchRecords(from startDate: Date, to endDate: Date) -> [HabitRecord] {
        guard persistenceController.canFetchSafely("HabitService.fetchRecords") else { return [] }
        let request = HabitRecord.fetchRequest()
        // 半开区间 [startDate, endDate)
        request.predicate = NSPredicate(
            format: "date >= %@ AND date < %@",
            startDate as NSDate,
            endDate as NSDate
        )
        request.sortDescriptors = [NSSortDescriptor(keyPath: \HabitRecord.date, ascending: false)]
        do {
            return try viewContext.fetch(request)
        } catch {
            print("获取区间打卡记录失败：\(error.localizedDescription)")
            return []
        }
    }

    func recalculateStreak(for habit: Habit) {
        let records = habit.records
        guard !records.isEmpty else {
            habit.currentStreak = 0
            saveAndReport()
            return
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // 根据频率确定周期组件（判据收口：走 HabitFrequency.rawValue，见文件头注释）
        let component: Calendar.Component
        switch habit.frequency {
        case HabitFrequency.weekly.rawValue:
            component = .weekOfYear
        case HabitFrequency.monthly.rawValue:
            component = .month
        default:
            component = .day
        }

        // 计算当前周期的起始时间
        var currentPeriodStart = today
        if component == .weekOfYear {
            let weekComponents = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)
            if let weekStart = calendar.date(from: weekComponents) {
                currentPeriodStart = weekStart
            }
        } else if component == .month {
            let monthComponents = calendar.dateComponents([.year, .month], from: today)
            if let monthStart = calendar.date(from: monthComponents) {
                currentPeriodStart = monthStart
            }
        }

        // 修复（2026-10-14 审查 P1-8）：今天尚未打卡（或用户刚撤销今日打卡）时，
        // 不应把连续天数直接清零 —— 应从昨天/上一个周期起算。
        // 例：连续 30 天的每日习惯，误触打卡按钮撤销今日打卡后旧实现显示 0 天。
        // 与 `AchievementService.computeStreak` 的容错语义对齐（判据收口到同一口径）。
        if !meetsTarget(records: records, habit: habit,
                        periodStart: currentPeriodStart, calendar: calendar, component: component),
           let previous = calendar.date(byAdding: component, value: -1, to: currentPeriodStart) {
            currentPeriodStart = previous
        }

        // 修复（2026-10-14 P2）：预聚合 —— 原实现每个周期都遍历一次全部 records
        // （O(周期数 × 记录数)），长 streak 用户每次打卡都会放大。
        var aggregatedTotals: [Date: Int32] = [:]
        for record in records {
            let key = periodStart(of: record.date, calendar: calendar, component: component)
            aggregatedTotals[key, default: 0] += Int32(record.count)
        }

        var streak: Int16 = 0
        let maxIterations: Int16 = 10000

        while streak < maxIterations {
            // 半开区间 [currentPeriodStart, nextPeriodStart)：避免 -1s 边界漏掉周期最后一秒的打卡
            let total = aggregatedTotals[currentPeriodStart] ?? 0

            if total >= habit.targetCount {
                streak += 1
                guard let previousStart = calendar.date(
                    byAdding: component, value: -1, to: currentPeriodStart
                ) else { break }
                currentPeriodStart = previousStart
            } else {
                break
            }
        }

        habit.currentStreak = streak
        if streak > habit.longestStreak {
            habit.longestStreak = streak
        }
        saveAndReport()
    }

    /// 某日期所属周期的起始日（与 recalculateStreak 的周期口径一致）
    private func periodStart(of date: Date, calendar: Calendar,
                             component: Calendar.Component) -> Date {
        switch component {
        case .weekOfYear:
            let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
            return calendar.date(from: comps) ?? calendar.startOfDay(for: date)
        case .month:
            let comps = calendar.dateComponents([.year, .month], from: date)
            return calendar.date(from: comps) ?? calendar.startOfDay(for: date)
        default:
            return calendar.startOfDay(for: date)
        }
    }

    /// 单个周期内的打卡总数（半开区间 [start, next)，避免 -1s 边界漏掉周期最后一秒）
    private func periodTotal(records: Set<HabitRecord>, periodStart: Date,
                             calendar: Calendar, component: Calendar.Component) -> Int16 {
        guard let next = calendar.date(byAdding: component, value: 1, to: periodStart) else { return 0 }
        return records
            .filter { $0.date >= periodStart && $0.date < next }
            .reduce(0) { $0 + $1.count }
    }

    /// 该周期是否已达标（用于「今天未打卡则从上一周期起算」的容错判断）
    private func meetsTarget(records: Set<HabitRecord>, habit: Habit, periodStart: Date,
                             calendar: Calendar, component: Calendar.Component) -> Bool {
        periodTotal(records: records, periodStart: periodStart,
                    calendar: calendar, component: component) >= habit.targetCount
    }
}

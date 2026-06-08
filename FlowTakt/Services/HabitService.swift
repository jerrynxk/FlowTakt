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
    func recalculateStreak(for habit: Habit)
}

// MARK: - 习惯服务实现

final class HabitService: HabitServiceProtocol {
    private let persistenceController: PersistenceController

    private var viewContext: NSManagedObjectContext {
        persistenceController.viewContext
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
        habit.id = UUID()
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
        persistenceController.save()
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
        persistenceController.save()
    }

    func deleteHabit(_ habit: Habit) {
        viewContext.delete(habit)
        persistenceController.save()
    }

    @discardableResult
    func checkIn(habit: Habit, count: Int16, note: String?) -> HabitRecord {
        let record = HabitRecord(context: viewContext)
        record.id = UUID()
        record.date = Date()
        record.count = count
        record.note = note
        record.createdAt = Date()
        record.habit = habit
        persistenceController.save()
        recalculateStreak(for: habit)
        return record
    }

    func removeCheckIn(_ record: HabitRecord) {
        let habit = record.habit
        viewContext.delete(record)
        persistenceController.save()
        recalculateStreak(for: habit)
    }

    func fetchAllHabits() -> [Habit] {
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
        let request = HabitRecord.fetchRequest()
        request.predicate = NSPredicate(
            format: "habit == %@ AND date >= %@ AND date <= %@",
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

    func recalculateStreak(for habit: Habit) {
        let records = habit.records ?? []
        guard !records.isEmpty else {
            habit.currentStreak = 0
            persistenceController.save()
            return
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // 根据频率确定周期组件
        let component: Calendar.Component
        switch habit.frequency {
        case "weekly":
            component = .weekOfYear
        case "monthly":
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

        var streak: Int16 = 0

        while true {
            let periodEnd = calendar.date(byAdding: component, value: 1, to: currentPeriodStart)!
                .addingTimeInterval(-1)

            let periodTotal = records
                .filter { $0.date >= currentPeriodStart && $0.date <= periodEnd }
                .reduce(0) { $0 + $1.count }

            if periodTotal >= habit.targetCount {
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
        persistenceController.save()
    }
}

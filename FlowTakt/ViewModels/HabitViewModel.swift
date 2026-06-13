import Foundation
import Combine
import CoreData

// MARK: - HabitViewModel

final class HabitViewModel: ObservableObject {
    // MARK: - Dependencies

    private let habitService: HabitServiceProtocol
    private let persistenceController: PersistenceController

    private var viewContext: NSManagedObjectContext {
        persistenceController.viewContext
    }

    // MARK: - Published Properties

    /// 所有习惯
    @Published var habits: [Habit] = []
    /// 当前选中的习惯
    @Published var selectedHabit: Habit? = nil

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init(habitService: HabitServiceProtocol, persistenceController: PersistenceController) {
        self.habitService = habitService
        self.persistenceController = persistenceController

        // 初始化时加载数据
        loadHabits()

        // 监听 CoreData 上下文变化，自动刷新
        NotificationCenter.default.publisher(
            for: .NSManagedObjectContextObjectsDidChange,
            object: viewContext
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.loadHabits()
        }
        .store(in: &cancellables)
    }

    // MARK: - Public Methods

    /// 加载所有习惯
    func loadHabits() {
        habits = habitService.fetchAllHabits()
    }

    /// 创建新习惯
    /// - Parameters:
    ///   - name: 习惯名称
    ///   - descriptionText: 描述（可选）
    ///   - iconName: 图标名称（可选）
    ///   - colorHex: 颜色十六进制值（可选）
    ///   - frequency: 频率（daily / weekly / monthly）
    ///   - targetCount: 目标次数
    func createHabit(
        name: String,
        descriptionText: String? = nil,
        iconName: String? = nil,
        colorHex: String? = nil,
        frequency: String = "daily",
        targetCount: Int16 = 1
    ) {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        _ = habitService.createHabit(
            name: name,
            descriptionText: descriptionText,
            iconName: iconName,
            colorHex: colorHex,
            frequency: frequency,
            targetCount: targetCount
        )

        loadHabits()
    }

    /// 删除习惯
    /// - Parameter habit: 要删除的习惯
    func deleteHabit(_ habit: Habit) {
        habitService.deleteHabit(habit)
        if selectedHabit?.id == habit.id {
            selectedHabit = nil
        }
        loadHabits()
    }

    /// 打卡
    /// - Parameter habit: 要打卡的习惯
    func checkIn(habit: Habit) {
        _ = habitService.checkIn(habit: habit, count: 1, note: nil)
        loadHabits()
    }

    /// 移除打卡记录
    /// - Parameter record: 要移除的打卡记录
    func removeCheckIn(record: HabitRecord) {
        habitService.removeCheckIn(record)
        loadHabits()
    }

    /// 获取指定习惯在最近 N 天内的打卡记录
    /// - Parameters:
    ///   - habit: 习惯
    ///   - days: 天数
    /// - Returns: 打卡记录数组
    func records(for habit: Habit, in days: Int) -> [HabitRecord] {
        let calendar = Calendar.current
        let endDate = Date()
        let startDate = calendar.date(byAdding: .day, value: -days, to: endDate)!
        return habitService.fetchHabitRecords(habit: habit, from: startDate, to: endDate)
    }

    /// 检查指定习惯在特定日期是否有打卡记录
    /// - Parameters:
    ///   - habit: 习惯
    ///   - date: 日期
    /// - Returns: 是否有打卡记录
    func dayHasRecord(habit: Habit, date: Date) -> Bool {
        let startOfDay = date.startOfDay
        let endOfDay = date.endOfDay
        let records = habitService.fetchHabitRecords(habit: habit, from: startOfDay, to: endOfDay)
        return !records.isEmpty
    }
}

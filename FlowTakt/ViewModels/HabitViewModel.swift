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
    /// 热力图：日期 → 当日打卡次数（跨习惯聚合，经 Service 查询，替代 View 直连 viewContext）
    @Published var heatmapCounts: [Date: Int] = [:]
    /// 热力图：区间内打卡总次数
    @Published var heatmapTotalCheckIns: Int = 0

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()
    /// 打卡防双击标志：快速连点只创建一条记录（400ms 窗口）
    private var isCheckingIn = false

    // MARK: - Init

    init(habitService: HabitServiceProtocol, persistenceController: PersistenceController) {
        self.habitService = habitService
        self.persistenceController = persistenceController

        // 初始化时加载数据
        loadHabits()
        reloadHeatmap(weeks: 17)

        // 监听 CoreData 上下文变化，自动刷新
        NotificationCenter.default.publisher(
            for: .NSManagedObjectContextObjectsDidChange,
            object: viewContext
        )
        .receive(on: DispatchQueue.main)
        .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.loadHabits()
            self?.reloadHeatmap(weeks: 17)
        }
        .store(in: &cancellables)

        // 监听数据库重置通知，立即清空旧 ManagedObject 引用防止崩溃
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDatabaseWillReset),
            name: .databaseWillReset,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDatabaseDidReset),
            name: .databaseDidReset,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Private

    @objc private func handleDatabaseWillReset() {
        habits = []
        selectedHabit = nil
    }

    @objc private func handleDatabaseDidReset() {
        DispatchQueue.main.async { [weak self] in
            self?.loadHabits()
            // 审查 #20：数据库重置后热力图一并重载，避免残留旧数据
            self?.reloadHeatmap(weeks: 17)
        }
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
        frequency: String = HabitFrequency.daily.rawValue,
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
        // 触觉反馈：删除为破坏性操作
        HapticManager.shared.mediumImpact()
        habitService.deleteHabit(habit)
        if selectedHabit?.id == habit.id {
            selectedHabit = nil
        }
        loadHabits()
    }

    /// 打卡（带 400ms 防双击：快速连点只创建一条记录，避免同屏数据重复）
    /// - Parameter habit: 要打卡的习惯
    func checkIn(habit: Habit) {
        guard !isCheckingIn else { return }
        isCheckingIn = true
        // 触觉反馈：打卡成功（轻量选择反馈）
        HapticManager.shared.selectionFeedback()
        _ = habitService.checkIn(habit: habit, count: 1, note: nil)
        loadHabits()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.isCheckingIn = false
        }
    }

    /// 移除打卡记录
    /// - Parameter record: 要移除的打卡记录
    func removeCheckIn(record: HabitRecord) {
        // 触觉反馈：取消打卡
        HapticManager.shared.selectionFeedback()
        habitService.removeCheckIn(record)
        loadHabits()
    }

    /// 加载热力图数据：拉取最近 N 周全部习惯的打卡记录，按天聚合（经 Service）
    /// 使用半开区间 [start, 明日0点)，保证今天的记录也被包含
    /// - Parameter weeks: 覆盖周数（17 周 ≈ 119 天）
    func reloadHeatmap(weeks: Int) {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -(weeks * 7 - 1), to: todayStart),
              let tomorrow = calendar.date(byAdding: .day, value: 1, to: todayStart) else { return }
        let records = habitService.fetchRecords(from: start, to: tomorrow)
        var map: [Date: Int] = [:]
        for r in records {
            map[calendar.startOfDay(for: r.date), default: 0] += Int(r.count)
        }
        heatmapCounts = map
        heatmapTotalCheckIns = records.reduce(0) { $0 + Int($1.count) }
    }

    /// 获取指定习惯在最近 N 天内的打卡记录
    /// - Parameters:
    ///   - habit: 习惯
    ///   - days: 天数
    /// - Returns: 打卡记录数组
    func records(for habit: Habit, in days: Int) -> [HabitRecord] {
        let calendar = Calendar.current
        let endDate = Date()
        // 审查 #13：guard 替代强制解包
        guard let startDate = calendar.date(byAdding: .day, value: -days, to: endDate) else { return [] }
        return habitService.fetchHabitRecords(habit: habit, from: startDate, to: endDate)
    }

    /// 检查指定习惯在特定日期是否有打卡记录（半开区间 [date, 次日)）
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

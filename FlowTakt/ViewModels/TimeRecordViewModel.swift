import Foundation
import Combine
import CoreData

// MARK: - TimeRecordViewModel

final class TimeRecordViewModel: ObservableObject {
    // MARK: - Dependencies

    private let timeRecordService: TimeRecordServiceProtocol
    private let persistenceController: PersistenceController

    private var viewContext: NSManagedObjectContext {
        persistenceController.viewContext
    }

    // MARK: - Published Properties

    /// 所有时间记录
    @Published var records: [TimeRecord] = []
    /// 是否正在记录
    @Published var isRecording: Bool = false
    /// 当前正在记录的条目
    @Published var currentRecord: TimeRecord? = nil
    /// 选中的日期
    @Published var selectedDate: Date = Date()
    /// 今日总时长
    @Published var totalDurationToday: Double = 0

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init(timeRecordService: TimeRecordServiceProtocol, persistenceController: PersistenceController) {
        self.timeRecordService = timeRecordService
        self.persistenceController = persistenceController

        // 初始化时加载数据
        loadRecords()
        refreshTodayTotal()

        // 监听 CoreData 上下文变化，自动刷新
        NotificationCenter.default.publisher(
            for: .NSManagedObjectContextObjectsDidChange,
            object: viewContext
        )
        .receive(on: DispatchQueue.main)
        .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.loadRecords()
            self?.refreshTodayTotal()
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
        records = []
        currentRecord = nil
        isRecording = false
        totalDurationToday = 0
        // 修复（2026-10-15 审查 P2-V6）：与同类 VM 一致，重置后日期视图回到今天
        selectedDate = Date()
    }

    @objc private func handleDatabaseDidReset() {
        DispatchQueue.main.async { [weak self] in
            self?.loadRecords()
            self?.refreshTodayTotal()
        }
    }

    // MARK: - Public Methods

    /// 加载所有时间记录
    /// 修复（2026-10-14 P2）：与库内「未闭合记录」对账 —— App 被强杀时会留下
    /// `endTime == nil` 的记录；此前 `isRecording` 恒为 false，于是用户可以再开一条计时，
    /// 旧记录永远停不了表（界面上也无法再停止它）。这里把未闭合记录恢复为「进行中」。
    func loadRecords() {
        records = timeRecordService.fetchAllRecords()

        // 恢复未闭合记录（强杀残留）。只在「本进程还没在计时」时接管，
        // 避免每次 loadRecords 都重复发布 isRecording（会打乱订阅方的 expectation 计数）。
        if currentRecord == nil, !isRecording,
           let open = records.first(where: { $0.endTime == nil }) {
            currentRecord = open
            isRecording = true
        }
    }

    /// 开始记录时间
    /// - Parameters:
    ///   - task: 关联的任务（可选）
    ///   - note: 备注（可选）
    ///   - project: 项目名称（可选）
    ///   - tag: 标签（可选）
    func startRecording(task: Task? = nil, note: String? = nil, project: String? = nil, tag: Tag? = nil) {
        // 防重：正在录制时忽略重复调用，避免覆盖 currentRecord 导致前一条记录永不停表
        guard !isRecording else { return }
        let record = timeRecordService.startRecording(task: task, note: note, project: project, tag: tag)
        currentRecord = record
        isRecording = true
        loadRecords()
        refreshTodayTotal()
    }

    /// 当前是否处于暂停段（判据收口在持久化字段，跨进程恢复有效）
    var isPaused: Bool {
        currentRecord?.pauseStartDate != nil
    }

    /// 停止当前记录
    func stopRecording() {
        guard let record = currentRecord else { return }
        timeRecordService.stopRecording(record)
        currentRecord = nil
        isRecording = false
        loadRecords()
        refreshTodayTotal()
    }

    /// 暂停正计时（用户反馈 2026-11-17）：计时中的净时长冻结，暂停段不计入统计。
    func pauseRecording() {
        guard let record = currentRecord else { return }
        timeRecordService.pauseRecording(record)
        loadRecords()
    }

    /// 继续正计时
    func resumeRecording() {
        guard let record = currentRecord else { return }
        timeRecordService.resumeRecording(record)
        loadRecords()
    }

    /// 当前净计时秒数（扣除暂停段），供 UI 实时显示。
    func currentNetElapsed() -> TimeInterval {
        guard let record = currentRecord else { return 0 }
        return timeRecordService.netElapsedSeconds(for: record)
    }

    /// 删除指定记录
    /// - Parameter record: 要删除的记录
    func deleteRecord(_ record: TimeRecord) {
        // 如果删除的是当前记录，同步状态
        if record == currentRecord {
            currentRecord = nil
            isRecording = false
        }
        timeRecordService.deleteRecord(record)
        loadRecords()
        refreshTodayTotal()
    }

    /// 多选删除（修复 2026-10-14 审查 T1：越界守卫下沉到 ViewModel，才可被单测覆盖）
    ///
    /// 崩溃修复（2026-10-02）：`recordsForDate` 是**计算属性**，每次访问都会基于最新的
    /// `records` 重新 filter + sort；而 `deleteRecord` 内部会 `loadRecords()` 把数组整体替换，
    /// 导致同一轮删除中后续索引失效 → `recordsForDate[index]` 越界触发
    /// `Fatal error: Index out of range`。
    ///
    /// 修复：进入循环前先取一次快照，并防御越界。索引语义 = 用户在列表中所见的位置，
    /// 因此**按快照删除全部选中项**（不再因源数据收缩而漏删）。
    func deleteRecords(at indexSet: IndexSet, in records: [TimeRecord]) {
        let snapshot = records
        for index in indexSet where snapshot.indices.contains(index) {
            deleteRecord(snapshot[index])
        }
    }

    /// 刷新今日总时长
    func refreshTodayTotal() {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: selectedDate)
        // 审查修复（2026-08-12）：guard 替代强制解包
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return }
        totalDurationToday = timeRecordService.getTotalDuration(from: startOfDay, to: endOfDay)
    }
}

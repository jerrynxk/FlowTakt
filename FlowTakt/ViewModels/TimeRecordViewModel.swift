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
    }

    @objc private func handleDatabaseDidReset() {
        DispatchQueue.main.async { [weak self] in
            self?.loadRecords()
            self?.refreshTodayTotal()
        }
    }

    // MARK: - Public Methods

    /// 加载所有时间记录
    func loadRecords() {
        records = timeRecordService.fetchAllRecords()
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

    /// 停止当前记录
    func stopRecording() {
        guard let record = currentRecord else { return }
        timeRecordService.stopRecording(record)
        currentRecord = nil
        isRecording = false
        loadRecords()
        refreshTodayTotal()
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

    /// 刷新今日总时长
    func refreshTodayTotal() {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: selectedDate)
        // 审查修复（2026-08-12）：guard 替代强制解包
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return }
        totalDurationToday = timeRecordService.getTotalDuration(from: startOfDay, to: endOfDay)
    }
}

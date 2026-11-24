import Foundation
import CoreData

// MARK: - TimeRecordService 协议

protocol TimeRecordServiceProtocol {
    func startRecording(task: Task?, note: String?, project: String?, tag: Tag?) -> TimeRecord
    func stopRecording(_ record: TimeRecord)
    /// 暂停正计时（用户反馈 2026-11-17）：记录暂停段起点，暂停期间不计入时长。
    func pauseRecording(_ record: TimeRecord)
    /// 恢复正计时：把当前暂停段累计到 pausedDuration 并清除起点。
    func resumeRecording(_ record: TimeRecord)
    /// 当前净计时秒数（扣除所有暂停段），供实时显示与结束时落库共用同一判据。
    func netElapsedSeconds(for record: TimeRecord) -> TimeInterval
    func updateRecord(_ record: TimeRecord, note: String?, project: String?, isBillable: Bool?, tag: Tag?)
    func deleteRecord(_ record: TimeRecord)
    func fetchAllRecords() -> [TimeRecord]
    func fetchRecords(from: Date, to: Date) -> [TimeRecord]
    func fetchRecordsForTask(_ task: Task) -> [TimeRecord]
    func getTotalDuration(from: Date, to: Date) -> Double
    func getDurationByProject(from: Date, to: Date) -> [(project: String, duration: Double)]
}

// MARK: - 时间记录服务实现

@MainActor
final class TimeRecordService: TimeRecordServiceProtocol {
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
            onError?(AppError.coreDataSaveFailed(NSError(domain: "FlowTakt.TimeRecordService",
                                                         code: NSFileWriteUnknownError)))
        }
    }

    init(persistenceController: PersistenceController) {
        self.persistenceController = persistenceController
    }

    // MARK: - 创建与停止

    func startRecording(task: Task?, note: String?, project: String?, tag: Tag?) -> TimeRecord {
        let record = TimeRecord(context: viewContext)
        record.storageId = UUID()
        record.startTime = Date()
        record.duration = 0
        record.pausedDuration = 0
        record.pauseStartDate = nil
        record.note = note
        record.project = project
        record.isBillable = true
        record.createdAt = Date()
        record.updatedAt = Date()
        record.task = task
        record.tag = tag
        saveAndReport()
        return record
    }

    func stopRecording(_ record: TimeRecord) {
        let now = Date()
        // 若停止时仍处于暂停段，先把该段结算进 pausedDuration，
        // 保证 duration 只含净计时（判据与 netElapsedSeconds 一致）。
        if let pauseStart = record.pauseStartDate {
            record.pausedDuration += max(0, now.timeIntervalSince(pauseStart))
            record.pauseStartDate = nil
        }
        record.endTime = now
        record.duration = max(0, now.timeIntervalSince(record.startTime) - record.pausedDuration)
        record.updatedAt = now
        saveAndReport()
    }

    // MARK: - 暂停 / 继续（用户反馈 2026-11-17）

    func pauseRecording(_ record: TimeRecord) {
        guard record.endTime == nil, record.pauseStartDate == nil else { return }
        record.pauseStartDate = Date()
        record.updatedAt = Date()
        saveAndReport()
    }

    func resumeRecording(_ record: TimeRecord) {
        guard record.endTime == nil, let pauseStart = record.pauseStartDate else { return }
        record.pausedDuration += max(0, Date().timeIntervalSince(pauseStart))
        record.pauseStartDate = nil
        record.updatedAt = Date()
        saveAndReport()
    }

    /// 净计时秒数 = 挂钟经过 - 已结算暂停段 - 当前未结算暂停段。
    /// 结束后锁定为落库的 duration，避免 endTime 之后继续增长。
    func netElapsedSeconds(for record: TimeRecord) -> TimeInterval {
        if record.endTime != nil {
            return max(0, record.duration)
        }
        let now = Date()
        let wall = max(0, now.timeIntervalSince(record.startTime))
        let currentPause = record.pauseStartDate.map { max(0, now.timeIntervalSince($0)) } ?? 0
        return max(0, wall - record.pausedDuration - currentPause)
    }

    // MARK: - 更新与删除

    func updateRecord(_ record: TimeRecord, note: String?, project: String?, isBillable: Bool?, tag: Tag?) {
        if let note = note { record.note = note }
        if let project = project { record.project = project }
        if let isBillable = isBillable { record.isBillable = isBillable }
        if let tag = tag { record.tag = tag }
        record.updatedAt = Date()
        saveAndReport()
    }

    func deleteRecord(_ record: TimeRecord) {
        viewContext.delete(record)
        saveAndReport()
    }

    // MARK: - 查询

    func fetchAllRecords() -> [TimeRecord] {
        guard persistenceController.canFetchSafely("TimeRecordService.fetchAllRecords") else { return [] }
        let request = TimeRecord.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \TimeRecord.startTime, ascending: false)]
        do {
            return try viewContext.fetch(request)
        } catch {
            print("获取时间记录失败：\(error.localizedDescription)")
            return []
        }
    }

    func fetchRecords(from: Date, to: Date) -> [TimeRecord] {
        guard persistenceController.canFetchSafely("TimeRecordService.fetchRecords") else { return [] }
        let request = TimeRecord.fetchRequest()
        request.predicate = NSPredicate(format: "startTime >= %@ AND startTime < %@", from as NSDate, to as NSDate)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \TimeRecord.startTime, ascending: false)]
        do {
            return try viewContext.fetch(request)
        } catch {
            print("获取时间记录失败（日期范围）：\(error.localizedDescription)")
            return []
        }
    }

    func fetchRecordsForTask(_ task: Task) -> [TimeRecord] {
        guard persistenceController.canFetchSafely("TimeRecordService.fetchRecordsForTask") else { return [] }
        let request = TimeRecord.fetchRequest()
        request.predicate = NSPredicate(format: "task == %@", task)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \TimeRecord.startTime, ascending: false)]
        do {
            return try viewContext.fetch(request)
        } catch {
            print("获取任务时间记录失败：\(error.localizedDescription)")
            return []
        }
    }

    // MARK: - 统计

    func getTotalDuration(from: Date, to: Date) -> Double {
        let records = fetchRecords(from: from, to: to)
        return records.reduce(0) { $0 + $1.duration }
    }

    func getDurationByProject(from: Date, to: Date) -> [(project: String, duration: Double)] {
        let records = fetchRecords(from: from, to: to)
        let grouped = Dictionary(grouping: records) { record -> String in
            record.project ?? L10n.shared.未分类
        }
        return grouped.map { (project, records) in
            let total = records.reduce(0) { $0 + $1.duration }
            return (project: project, duration: total)
        }
    }
}

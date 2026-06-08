import Foundation
import CoreData

// MARK: - TimeRecordService 协议

protocol TimeRecordServiceProtocol {
    func startRecording(task: Task?, note: String?, project: String?, tag: Tag?) -> TimeRecord
    func stopRecording(_ record: TimeRecord)
    func updateRecord(_ record: TimeRecord, note: String?, project: String?, isBillable: Bool?, tag: Tag?)
    func deleteRecord(_ record: TimeRecord)
    func fetchAllRecords() -> [TimeRecord]
    func fetchRecords(from: Date, to: Date) -> [TimeRecord]
    func fetchRecordsForTask(_ task: Task) -> [TimeRecord]
    func getTotalDuration(from: Date, to: Date) -> Double
    func getDurationByProject(from: Date, to: Date) -> [(project: String, duration: Double)]
}

// MARK: - 时间记录服务实现

final class TimeRecordService: TimeRecordServiceProtocol {
    private let persistenceController: PersistenceController

    private var viewContext: NSManagedObjectContext {
        persistenceController.viewContext
    }

    init(persistenceController: PersistenceController) {
        self.persistenceController = persistenceController
    }

    // MARK: - 创建与停止

    func startRecording(task: Task?, note: String?, project: String?, tag: Tag?) -> TimeRecord {
        let record = TimeRecord(context: viewContext)
        record.id = UUID()
        record.startTime = Date()
        record.duration = 0
        record.note = note
        record.project = project
        record.isBillable = true
        record.createdAt = Date()
        record.updatedAt = Date()
        record.task = task
        record.tag = tag
        persistenceController.save()
        return record
    }

    func stopRecording(_ record: TimeRecord) {
        let now = Date()
        record.endTime = now
        record.duration = now.timeIntervalSince(record.startTime)
        record.updatedAt = now
        persistenceController.save()
    }

    // MARK: - 更新与删除

    func updateRecord(_ record: TimeRecord, note: String?, project: String?, isBillable: Bool?, tag: Tag?) {
        if let note = note { record.note = note }
        if let project = project { record.project = project }
        if let isBillable = isBillable { record.isBillable = isBillable }
        if let tag = tag { record.tag = tag }
        record.updatedAt = Date()
        persistenceController.save()
    }

    func deleteRecord(_ record: TimeRecord) {
        viewContext.delete(record)
        persistenceController.save()
    }

    // MARK: - 查询

    func fetchAllRecords() -> [TimeRecord] {
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
            record.project ?? "未分类"
        }
        return grouped.map { (project, records) in
            let total = records.reduce(0) { $0 + $1.duration }
            return (project: project, duration: total)
        }
    }
}

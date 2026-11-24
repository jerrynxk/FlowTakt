import Foundation
import CoreData

extension TimeRecord {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<TimeRecord> {
        let request = NSFetchRequest<TimeRecord>(entityName: "TimeRecord")
        // 日志型实体数据增长后内存飙升风险，设置 fetchBatchSize 启用分批加载
        request.fetchBatchSize = 50
        return request
    }

    /// 存储层 id（保持与模型 optional 一致，2026-10-15 崩溃修复）。
    /// 读取请用 `id` 计算属性（nil 兜底）；写入请用本属性（`obj.storageId = UUID()`）。
    @NSManaged @objc(id) public var storageId: UUID?
    @NSManaged public var startTime: Date
    @NSManaged public var endTime: Date?
    @NSManaged public var duration: Double
    @NSManaged public var note: String?
    @NSManaged public var project: String?
    /// 暂停段累计秒数（正计时暂停/继续，用户反馈 2026-11-17）。落库以支持跨进程恢复。
    @NSManaged public var pausedDuration: Double
    /// 当前暂停段起点；nil 表示正在计时或已结束。落库以支持强杀后恢复暂停态。
    @NSManaged public var pauseStartDate: Date?
    @NSManaged public var isBillable: Bool
    @NSManaged public var createdAt: Date
    @NSManaged public var updatedAt: Date

    @NSManaged public var task: Task?
    @NSManaged public var tag: Tag?
}

extension TimeRecord: Identifiable {
    /// 永不 trap 的对外 id（2026-10-15）：存储缺失（异常数据）时返回固定占位值，
    /// 避免 NSManaged 非 optional 桥接 nil 触发 EXC_BREAKPOINT（实机崩溃实锤）。
    public var id: UUID { storageId ?? Self.missingIdPlaceholder }

    private static let missingIdPlaceholder = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0,
                                                          0, 0, 0, 0, 0, 0, 0, 0))
}

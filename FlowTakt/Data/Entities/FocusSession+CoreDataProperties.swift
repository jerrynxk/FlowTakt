import Foundation
import CoreData

extension FocusSession {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<FocusSession> {
        let request = NSFetchRequest<FocusSession>(entityName: "FocusSession")
        // 日志型实体数据增长后内存飙升风险，设置 fetchBatchSize 启用分批加载
        request.fetchBatchSize = 50
        return request
    }

    /// 存储层 id（保持与模型 optional 一致，2026-10-15 崩溃修复）。
    /// 读取请用 `id` 计算属性（nil 兜底）；写入请用本属性（`obj.storageId = UUID()`）。
    @NSManaged @objc(id) public var storageId: UUID?
    @NSManaged public var startTime: Date
    @NSManaged public var endTime: Date?
    @NSManaged public var plannedDuration: Double
    @NSManaged public var actualDuration: Double
    @NSManaged public var phase: String
    @NSManaged public var roundIndex: Int16
    @NSManaged public var status: String
    @NSManaged public var earnedPoints: Int16
    @NSManaged public var interruptionReason: String?
    @NSManaged public var createdAt: Date
    @NSManaged public var updatedAt: Date

    @NSManaged public var task: Task?
    @NSManaged public var tag: Tag?
}

extension FocusSession: Identifiable {
    /// 永不 trap 的对外 id（2026-10-15）：存储缺失（异常数据）时返回固定占位值，
    /// 避免 NSManaged 非 optional 桥接 nil 触发 EXC_BREAKPOINT（实机崩溃实锤）。
    public var id: UUID { storageId ?? Self.missingIdPlaceholder }

    private static let missingIdPlaceholder = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0,
                                                          0, 0, 0, 0, 0, 0, 0, 0))
}

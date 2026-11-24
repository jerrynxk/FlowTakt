import Foundation
import CoreData

extension Achievement {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Achievement> {
        return NSFetchRequest<Achievement>(entityName: "Achievement")
    }

    /// 存储层 id（保持与模型 optional 一致）。
    ///
    /// 修复（2026-10-15 线上崩溃）：模型为 CloudKit 兼容已 optional 化本属性，但此前
    /// Swift 声明仍为非 optional UUID —— 存储为 nil 时读取会经
    /// `UUID._unconditionallyBridgeFromObjectiveC` 触发 EXC_BREAKPOINT（13 Pro 实机
    /// 崩溃 4 次实锤：ForEach 渲染读 id 时崩溃）。现改为 optional 存储 + 对外计算属性
    /// `id`（nil 兜底），写入路径请使用本属性（如 `obj.storageId = UUID()`）。
    @NSManaged @objc(id) public var storageId: UUID?
    @NSManaged public var identifier: String
    @NSManaged public var title: String
    @NSManaged public var descriptionText: String?
    @NSManaged public var iconName: String?
    @NSManaged public var category: String
    @NSManaged public var thresholdValue: Int16
    @NSManaged public var isUnlocked: Bool
    @NSManaged public var unlockedAt: Date?
    @NSManaged public var createdAt: Date
}

extension Achievement: Identifiable {
    /// 永不 trap 的对外 id（2026-10-15）：存储缺失（异常数据）时返回固定占位值，
    /// 保证 ForEach / 排序 / 查询渲染路径不崩溃（占位仅在异常数据下出现）。
    public var id: UUID { storageId ?? Self.missingIdPlaceholder }

    private static let missingIdPlaceholder = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0,
                                                          0, 0, 0, 0, 0, 0, 0, 0))
}

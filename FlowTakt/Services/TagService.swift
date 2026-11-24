import Foundation
import CoreData

// MARK: - TagService 协议

protocol TagServiceProtocol {
    /// 全部标签（按名称排序，保证 UI 顺序稳定）
    func fetchAllTags() -> [Tag]
    /// 创建标签。同名（忽略首尾空白、大小写）时返回已有标签，避免重复。
    func createTag(name: String, colorHex: String?) -> Tag?
    func renameTag(_ tag: Tag, to name: String)
    func setTagColor(_ tag: Tag, colorHex: String?)
    /// 删除标签。数据模型中所有关系均为 Nullify：任务/专注会话/时间记录自动解除关联，不级联删除数据。
    func deleteTag(_ tag: Tag)
    /// 用给定集合整体替换任务的标签（全量写，调用方无需自己维护增删差量）
    func setTags(_ tags: Set<Tag>, on task: Task)
}

// MARK: - 标签服务实现

@MainActor
final class TagService: TagServiceProtocol {
    private let persistenceController: PersistenceController

    /// 错误回调：供 ViewModel 层监听 Service 内部错误（与其余 Service 同一契约）
    var onError: ((Error) -> Void)?

    private var viewContext: NSManagedObjectContext {
        persistenceController.viewContext
    }
    /// save 失败统一上报（判据收口，与 TaskService/TimeRecordService 一致）
    func saveAndReport() {
        if !persistenceController.save() {
            onError?(AppError.coreDataSaveFailed(NSError(domain: "FlowTakt.TagService",
                                                         code: NSFileWriteUnknownError)))
        }
    }

    init(persistenceController: PersistenceController) {
        self.persistenceController = persistenceController
    }

    // MARK: - 查询

    func fetchAllTags() -> [Tag] {
        guard persistenceController.canFetchSafely("TagService.fetchAllTags") else { return [] }
        let request = Tag.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Tag.name, ascending: true)]
        do {
            return try viewContext.fetch(request)
        } catch {
            print("获取标签列表失败：\(error.localizedDescription)")
            onError?(error)
            return []
        }
    }

    // MARK: - 创建与编辑

    func createTag(name: String, colorHex: String?) -> Tag? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard persistenceController.canFetchSafely("TagService.createTag") else { return nil }

        // 同名去重（大小写不敏感）：返回已有标签，避免用户连点产生重复项
        let request = Tag.fetchRequest()
        request.predicate = NSPredicate(format: "name ==[c] %@", trimmed)
        request.fetchLimit = 1
        if let existing = try? viewContext.fetch(request).first {
            return existing
        }

        let tag = Tag(context: viewContext)
        tag.storageId = UUID()
        tag.name = trimmed
        tag.colorHex = colorHex
        tag.createdAt = Date()
        saveAndReport()
        return tag
    }

    func renameTag(_ tag: Tag, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        tag.name = trimmed
        saveAndReport()
    }

    func setTagColor(_ tag: Tag, colorHex: String?) {
        tag.colorHex = colorHex
        saveAndReport()
    }

    func deleteTag(_ tag: Tag) {
        // 关系删除规则均为 Nullify（xcdatamodel 定义）：任务/会话/时间记录仅解除关联。
        // 时间记录与专注会话的归属统计由 resolvedTag 兜底链自然回落到「未分类」。
        viewContext.delete(tag)
        saveAndReport()
    }

    // MARK: - 任务关联

    func setTags(_ tags: Set<Tag>, on task: Task) {
        task.tags = tags
        task.updatedAt = Date()
        saveAndReport()
    }
}

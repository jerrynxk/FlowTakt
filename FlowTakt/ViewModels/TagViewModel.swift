import Foundation
import Combine
import CoreData

// MARK: - TagViewModel
//
// 标签功能的 ViewModel（用户反馈 2026-11-19：App 内无标签创建入口，
// 统计页「按标签统计」恒为「未分类」）。职责：
// 1. 持有标签列表供编辑页 chips 选择；
// 2. 封装 TagService 的创建/重命名/删除/任务关联；
// 3. 监听 viewContext 对象变化自动刷新（CloudKit 导入远端标签时同步出现）。

final class TagViewModel: ObservableObject {
    // MARK: - Dependencies

    private let tagService: TagServiceProtocol
    private let persistenceController: PersistenceController

    private var viewContext: NSManagedObjectContext {
        persistenceController.viewContext
    }

    // MARK: - Published Properties

    /// 全部标签（按名称排序）
    @Published var tags: [Tag] = []

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init(tagService: TagServiceProtocol, persistenceController: PersistenceController) {
        self.tagService = tagService
        self.persistenceController = persistenceController

        loadTags()

        // 监听 CoreData 上下文变化自动刷新（与 TaskViewModel 同一模式：
        // 备份恢复 / CloudKit 导入产生的标签无需手动刷新）
        NotificationCenter.default.publisher(
            for: .NSManagedObjectContextObjectsDidChange,
            object: viewContext
        )
        .receive(on: DispatchQueue.main)
        .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.loadTags()
        }
        .store(in: &cancellables)

        // 数据库重置后清引用并重查（防止悬垂 NSManagedObject）
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

    // MARK: - 重置防护

    @objc private func handleDatabaseWillReset() {
        tags = []
    }

    @objc private func handleDatabaseDidReset() {
        DispatchQueue.main.async { [weak self] in
            self?.loadTags()
        }
    }

    // MARK: - Public Methods

    func loadTags() {
        tags = tagService.fetchAllTags()
    }

    /// 创建标签（同名去重由 Service 保证），成功后刷新列表并返回新标签。
    @discardableResult
    func createTag(name: String, colorHex: String?) -> Tag? {
        let tag = tagService.createTag(name: name, colorHex: colorHex)
        loadTags()
        return tag
    }

    func renameTag(_ tag: Tag, to name: String) {
        tagService.renameTag(tag, to: name)
        loadTags()
    }

    func deleteTag(_ tag: Tag) {
        HapticManager.shared.mediumImpact()
        tagService.deleteTag(tag)
        loadTags()
    }

    /// 全量替换任务标签（View 层禁直改 NSManagedObject，统一走本入口）
    func setTags(_ tags: Set<Tag>, on task: Task) {
        tagService.setTags(tags, on: task)
    }

    /// 按 id 解析标签集合（创建/编辑页保存时用：选择态只持有 id，避免跨 context 引用歧义）
    func resolveTags(ids: Set<UUID>) -> Set<Tag> {
        Set(tags.filter { ids.contains($0.id) })
    }
}

import Foundation
import CoreData

// MARK: - CoreData Stack

/// PersistenceController 错误类型
enum PersistenceError: LocalizedError {
    case storeURLNotFound

    var errorDescription: String? {
        switch self {
        case .storeURLNotFound:
            return L10n.shared.无法获取持久化存储URL
        }
    }
}

final class PersistenceController {
    static let shared = PersistenceController()

    /// 预览用 PersistenceController（内存存储 + Mock 数据）
    static var preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        let viewContext = controller.container.viewContext

        // 创建 Mock 任务
        let task1 = Task(context: viewContext)
        task1.id = UUID()
        task1.title = "撰写技术方案文档"
        task1.notes = "完成 v1.0 架构设计文档的编写"
        task1.estimatedPomodoros = 3
        task1.completedPomodoros = 1
        task1.priority = 2
        task1.status = TaskStatus.active.rawValue
        task1.displayOrder = 0
        task1.createdAt = Date()
        task1.updatedAt = Date()

        let task2 = Task(context: viewContext)
        task2.id = UUID()
        task2.title = "完成 PRD 编写"
        task2.notes = nil
        task2.estimatedPomodoros = 2
        task2.completedPomodoros = 2
        task2.priority = 2
        task2.status = TaskStatus.completed.rawValue
        task2.dueDate = Date()
        task2.completedAt = Date()
        task2.displayOrder = 1
        task2.createdAt = Date()
        task2.updatedAt = Date()

        // 创建 Mock 专注会话
        let session1 = FocusSession(context: viewContext)
        session1.id = UUID()
        session1.startTime = Date().addingTimeInterval(-3600)
        session1.endTime = Date().addingTimeInterval(-1800)
        session1.plannedDuration = 25 * 60
        session1.actualDuration = 25 * 60
        session1.phase = FocusPhase.focus.rawValue
        session1.roundIndex = 1
        session1.status = SessionStatus.completed.rawValue
        session1.earnedPoints = 10
        session1.createdAt = Date().addingTimeInterval(-3600)
        session1.updatedAt = Date().addingTimeInterval(-1800)

        let session2 = FocusSession(context: viewContext)
        session2.id = UUID()
        session2.startTime = Date().addingTimeInterval(-1800)
        session2.endTime = Date()
        session2.plannedDuration = 25 * 60
        session2.actualDuration = 25 * 60
        session2.phase = FocusPhase.focus.rawValue
        session2.roundIndex = 2
        session2.status = SessionStatus.completed.rawValue
        session2.earnedPoints = 10
        session2.task = task1
        session2.createdAt = Date().addingTimeInterval(-1800)
        session2.updatedAt = Date()

        // 创建 Mock 成就
        let achievement1 = Achievement(context: viewContext)
        achievement1.id = UUID()
        achievement1.identifier = "first_pomodoro"
        achievement1.title = "初次专注"
        achievement1.descriptionText = "完成你的第一个番茄钟"
        achievement1.iconName = "star.fill"
        achievement1.category = AchievementCategory.total.rawValue
        achievement1.thresholdValue = 1
        achievement1.isUnlocked = true
        achievement1.unlockedAt = Date().addingTimeInterval(-86400 * 3)
        achievement1.createdAt = Date().addingTimeInterval(-86400 * 3)

        let achievement2 = Achievement(context: viewContext)
        achievement2.id = UUID()
        achievement2.identifier = "pomodoros_10"
        achievement2.title = "专注新手"
        achievement2.descriptionText = "累计完成 10 个番茄钟"
        achievement2.iconName = "10.square.fill"
        achievement2.category = AchievementCategory.total.rawValue
        achievement2.thresholdValue = 10
        achievement2.isUnlocked = false
        achievement2.createdAt = Date().addingTimeInterval(-86400 * 3)

        // 创建 Mock 标签
        let tag = Tag(context: viewContext)
        tag.id = UUID()
        tag.name = "工作"
        tag.colorHex = "#4CAF50"
        tag.createdAt = Date()

        do {
            try viewContext.save()
        } catch {
            let nsError = error as NSError
            fatalError("预览数据创建失败：\(nsError), \(nsError.userInfo)")
        }

        return controller
    }()

    let container: NSPersistentContainer

    var viewContext: NSManagedObjectContext {
        return container.viewContext
    }

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "FlowTakt")

        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }

        // 配置持久化存储
        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                fatalError("CoreData 加载失败：\(error), \(error.userInfo)")
            }
        }

        // 冲突合并策略：属性级别的最新写入获胜
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    /// 保存当前上下文
    func save() {
        let context = container.viewContext
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            let nsError = error as NSError
            print("CoreData 保存失败：\(nsError), \(nsError.userInfo)")
        }
    }

    /// 创建后台上下文用于写操作
    func newBackgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return context
    }

    // MARK: - 数据库重置

    /// 重置数据库：销毁当前的所有持久化存储文件并重建空数据库
    /// - 删除 SQLite 及其附属文件（-wal, -shm）
    /// - 重新创建一个全新的空存储
    /// - 重置所有上下文
    /// - Throws: 重置过程中的错误
    func resetDatabase() throws {
        let coordinator = container.persistentStoreCoordinator
        let context = container.viewContext

        // 1. 保存当前未提交的变更
        if context.hasChanges {
            try context.save()
        }

        // 2. 获取当前存储的 URL
        guard let storeURL = container.persistentStoreDescriptions.first?.url else {
            throw PersistenceError.storeURLNotFound
        }

        // 3. 移除所有现有持久化存储
        for store in coordinator.persistentStores {
            try coordinator.remove(store)
        }

        // 4. 手动删除 SQLite 及其附属文件
        let fileManager = FileManager.default
        let filesToDelete = [
            storeURL,
            storeURL.appendingPathExtension("sqlite-wal"),
            storeURL.appendingPathExtension("sqlite-shm")
        ]

        for fileURL in filesToDelete {
            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.removeItem(at: fileURL)
            }
        }

        // 5. 重新添加空持久化存储（自动创建新的 SQLite 文件）
        let options: [String: Any] = [
            NSMigratePersistentStoresAutomaticallyOption: true,
            NSInferMappingModelAutomaticallyOption: true
        ]
        try coordinator.addPersistentStore(
            ofType: NSSQLiteStoreType,
            configurationName: nil,
            at: storeURL,
            options: options
        )

        // 6. 重置上下文
        context.reset()

        print("✅ 数据库已成功重置：\(storeURL.lastPathComponent)")
    }
}

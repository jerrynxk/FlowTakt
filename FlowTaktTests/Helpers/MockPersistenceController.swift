import Foundation
import CoreData

@testable import FlowTakt

// MARK: - MockPersistenceController
// 用于单元测试的内存 CoreData Stack
// 每个测试用例应当创建独立实例确保测试隔离
//
// Xcode Target 配置:
// - 添加至 FlowTaktTests Target
// - 模型复用 PersistenceController.sharedManagedObjectModel（App Bundle 内），
//   不再需要将 FlowTakt.xcdatamodeld 加入 Test Target 的 Bundle Resources，
//   同时避免测试进程中加载两份同名模型导致实体描述重复噪声

final class MockPersistenceController {
    let container: NSPersistentContainer

    var viewContext: NSManagedObjectContext {
        return container.viewContext
    }

    init() {
        container = NSPersistentContainer(name: "FlowTakt",
                                          managedObjectModel: PersistenceController.sharedManagedObjectModel)
        container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")

        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("MockPersistenceController 初始化失败: \(error)")
            }
        }
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    /// 创建全新的上下文（测试隔离用）
    /// 预留方法，当前测试未使用
    func newChildContext() -> NSManagedObjectContext {
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.parent = container.viewContext
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.automaticallyMergesChangesFromParent = true
        return context
    }

    /// 保存上下文
    func save() {
        let context = container.viewContext
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            print("MockPersistenceController 保存失败: \(error)")
        }
    }
}

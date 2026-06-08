import Foundation
import CoreData

// MARK: - MockPersistenceController
// 用于单元测试的内存 CoreData Stack
// 每个测试用例应当创建独立实例确保测试隔离
//
// Xcode Target 配置:
// - 添加至 FlowTaktTests Target
// - 需将 FlowTakt.xcdatamodeld 加入 Test Target 的 Bundle Resources

final class MockPersistenceController {
    let container: NSPersistentContainer

    var viewContext: NSManagedObjectContext {
        return container.viewContext
    }

    init() {
        // 使用 NSManagedObjectModel 合并所有实体的 .mom 文件
        guard let momURL = Bundle.main.url(forResource: "FlowTakt", withExtension: "momd"),
              let managedObjectModel = NSManagedObjectModel(contentsOf: momURL) else {
            // Fallback: 如果找不到 momd 文件（测试中可能未添加资源），
            // 使用内存自动生成的 managedObjectModel
            container = NSPersistentContainer(name: "FlowTakt")
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")

            container.loadPersistentStores { _, error in
                if let error = error {
                    fatalError("MockPersistenceController 初始化失败: \(error)")
                }
            }
            container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            return
        }

        container = NSPersistentContainer(name: "FlowTakt", managedObjectModel: managedObjectModel)
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
    func newChildContext() -> NSManagedObjectContext {
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.parent = container.viewContext
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
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

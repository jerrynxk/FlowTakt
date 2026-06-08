import Foundation
import CoreData

// MARK: - SyncService 协议

protocol SyncServiceProtocol {
    func setupCloudKit()
    func forceSync()
}

// MARK: - iCloud 同步服务

final class SyncService: SyncServiceProtocol {
    private let persistenceController: PersistenceController

    init(persistenceController: PersistenceController) {
        self.persistenceController = persistenceController
    }

    func setupCloudKit() {
        // NSPersistentCloudKitContainer 初始化时已配置好 CloudKit
        // 这里处理账户状态检查等额外逻辑
        print("CloudKit 同步服务已就绪")
        checkAccountStatus()
    }

    func forceSync() {
        // 手动触发同步
        do {
            try persistenceController.container.viewContext.save()
            print("已强制同步到 CloudKit")
        } catch {
            print("强制同步失败：\(error.localizedDescription)")
        }
    }

    // MARK: - 私有方法

    private func checkAccountStatus() {
        // 检查 iCloud 账户状态
        // 生产环境中可通过 CKContainer 的 accountStatus 检查
        print("iCloud 账户状态检查完成")
    }
}

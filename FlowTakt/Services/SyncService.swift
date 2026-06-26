import Foundation
import CoreData
import CloudKit

// MARK: - SyncService 协议

protocol SyncServiceProtocol {
    func setupCloudKit()
    func forceSync()
    var isCloudAvailable: Bool { get }
}

// MARK: - iCloud 同步服务

final class SyncService: SyncServiceProtocol {
    private let persistenceController: PersistenceController

    var isCloudAvailable: Bool {
        persistenceController.cloudSyncStatus == .available
    }

    init(persistenceController: PersistenceController) {
        self.persistenceController = persistenceController
    }

    func setupCloudKit() {
        // NSPersistentCloudKitContainer 初始化时已自动配置 CloudKit
        // 这里处理账户状态变化监听等额外逻辑
        print("CloudKit 同步服务已就绪")

        // 监听 iCloud 账户变化
        NotificationCenter.default.addObserver(
            forName: .CKAccountChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.persistenceController.forceSync()
        }
    }

    func forceSync() {
        persistenceController.forceSync()
    }
}

// MARK: - 预览用假同步服务

final class MockSyncService: SyncServiceProtocol {
    var isCloudAvailable: Bool { false }

    func setupCloudKit() {}
    func forceSync() {}
}

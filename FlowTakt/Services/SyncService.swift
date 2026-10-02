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
    /// iCloud 账户变化观察者 token：保存并在 deinit 移除，避免重复注册/泄漏
    private var accountObserver: NSObjectProtocol?

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

        // 幂等：重复调用时先移除旧观察者，避免多次注册导致账户变更时重复 forceSync
        if let accountObserver {
            NotificationCenter.default.removeObserver(accountObserver)
        }
        // 监听 iCloud 账户变化
        accountObserver = NotificationCenter.default.addObserver(
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

    deinit {
        if let accountObserver {
            NotificationCenter.default.removeObserver(accountObserver)
        }
    }
}

// MARK: - 预览用假同步服务

final class MockSyncService: SyncServiceProtocol {
    var isCloudAvailable: Bool { false }

    func setupCloudKit() {}
    func forceSync() {}
}

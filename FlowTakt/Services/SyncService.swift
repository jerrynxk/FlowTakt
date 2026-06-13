import Foundation
import CoreData
import CloudKit

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
        let container = CKContainer.default()
        container.accountStatus { [weak self] status, error in
            if let error = error {
                print("iCloud 账户状态检查失败：\(error.localizedDescription)")
                return
            }
            switch status {
            case .available:
                print("iCloud 账户可用，CloudKit 同步正常")
                self?.logAccountInfo(container: container)
            case .noAccount:
                print("警告：未登录 iCloud 账户，CloudKit 同步不可用")
            case .restricted:
                print("警告：iCloud 账户受限（家长控制或企业策略），CloudKit 同步不可用")
            case .couldNotDetermine:
                print("警告：无法确定 iCloud 账户状态，CloudKit 同步可能不可用")
            case .temporarilyUnavailable:
                print("警告：iCloud 账户暂不可用，请稍后重试")
            @unknown default:
                print("警告：未知的 iCloud 账户状态")
            }
        }
    }

    private func logAccountInfo(container: CKContainer) {
        container.fetchUserRecordID { recordID, error in
            if let error = error {
                print("获取 iCloud 用户记录失败：\(error.localizedDescription)")
                return
            }
            if let recordID = recordID {
                print("CloudKit 用户记录 ID：\(recordID.recordName)")
            }
        }
    }
}

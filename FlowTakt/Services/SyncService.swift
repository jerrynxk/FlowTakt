import Foundation
import CoreData
import CloudKit

// MARK: - 同步结果（用户反馈 2026-11-17：消除「同步请求已发送」假说明）

/// 手动同步的真实结果。UI 必须据此如实反馈，不得无条件显示「已触发」。
enum SyncOutcome: Equatable {
    /// 本地变更已保存，CloudKit 将在后台导出
    case savedLocalChanges
    /// 无本地变更；其它设备的更新由静默推送 / 回到前台时自动拉取
    case noLocalChanges
    /// iCloud 同步开关未开启（每台设备需各自开启）
    case syncDisabled
    /// iCloud 账户不可用（未登录 / 未授权）
    case accountUnavailable
    /// 开关已开但 store 尚未挂载 CloudKit
    case notMounted
    /// 存储未就绪或保存失败（附带真实原因）
    case failed(String)
}

// MARK: - SyncService 协议

protocol SyncServiceProtocol {
    func setupCloudKit()
    @discardableResult func forceSync() -> SyncOutcome
    /// 手动同步（2026-11-19 修复）：先刷新账户状态快照再执行，结果异步返回。
    /// 旧 forceSync 读启动时的一次性快照，重登 iCloud 后不重启 App 恒报「账户不可用」。
    func syncNow(completion: @escaping (SyncOutcome) -> Void)
    var isCloudAvailable: Bool { get }
    /// 底层挂载状态（2026-11-19）：设置页需要区分「检测中」「账户不可用」「已挂载」，
    /// 只靠 `isCloudAvailable` 的布尔值无法如实表达 —— 启动初期 store 尚在加载时会被
    /// 误报成「账户不可用」。
    var mountStatus: CloudSyncStatus { get }
}

extension SyncServiceProtocol {
    /// 默认实现：只区分可用 / 不可用（Mock 与既有实现无需改动即可编译）。
    var mountStatus: CloudSyncStatus { isCloudAvailable ? .available : .unavailable }

    /// 默认实现：不刷新状态、直接同步（Mock 与既有实现无需改动即可编译）。
    func syncNow(completion: @escaping (SyncOutcome) -> Void) {
        completion(forceSync())
    }
}

// MARK: - iCloud 同步服务

final class SyncService: SyncServiceProtocol {
    private let persistenceController: PersistenceController
    /// iCloud 账户变化观察者 token：保存并在 deinit 移除，避免重复注册/泄漏
    private var accountObserver: NSObjectProtocol?
    /// 幂等守卫（2026-10-15 审查 P2-S9）：重复调用 setupCloudKit 直接返回
    private var isSetup = false

    var isCloudAvailable: Bool {
        persistenceController.cloudSyncStatus == .available
    }

    /// 透传真实挂载状态（.notDetermined / .unavailable / .available）
    var mountStatus: CloudSyncStatus {
        persistenceController.cloudSyncStatus
    }

    init(persistenceController: PersistenceController) {
        self.persistenceController = persistenceController
    }

    func setupCloudKit() {
        guard !isSetup else { return }
        isSetup = true
        // NSPersistentCloudKitContainer 初始化时已自动配置 CloudKit
        // 这里处理账户状态变化监听等额外逻辑
        print("CloudKit 同步服务已就绪")

        // 监听 iCloud 账户变化
        accountObserver = NotificationCenter.default.addObserver(
            forName: .CKAccountChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // 修复（2026-11-19）：先刷新账户状态快照再同步。旧实现直接 forceSync，
            // 读到的是启动时设置的一次性快照 —— 重登 iCloud 后不重启 App，
            // 快照永远停留「不可用」，手动同步恒报「账户不可用」（用户实测命中）。
            guard let self else { return }
            self.persistenceController.refreshCloudAccountStatus { [weak self] in
                self?.forceSync()
            }
        }
    }

    @discardableResult
    func forceSync() -> SyncOutcome {
        persistenceController.forceSync()
    }

    /// 手动同步：先刷新账户状态快照（异步网络查询），拿到最新状态后再执行同步
    func syncNow(completion: @escaping (SyncOutcome) -> Void) {
        persistenceController.refreshCloudAccountStatus { [weak self] in
            completion(self?.forceSync() ?? .failed("同步服务已释放"))
        }
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
    /// 测试可配置：模拟手动同步返回的真实结果
    var forceSyncResult: SyncOutcome = .noLocalChanges

    func setupCloudKit() {}
    @discardableResult
    func forceSync() -> SyncOutcome { forceSyncResult }
}

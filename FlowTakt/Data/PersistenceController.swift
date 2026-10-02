import Foundation
import CoreData
import CloudKit
import Combine

// MARK: - 通知

extension Notification.Name {
    /// 数据库即将重置，所有 ViewModel 应立即清空 ManagedObject 引用
    static let databaseWillReset = Notification.Name("com.flowtakt.databaseWillReset")
    /// 数据库已重置，所有 ViewModel 应重新加载数据
    static let databaseDidReset = Notification.Name("com.flowtakt.databaseDidReset")
    /// 提醒数据（生日/纪念日/客户拜访）发生变化，ReminderService 据此重排通知并刷新小组件
    static let remindersDataChanged = Notification.Name("com.flowtakt.remindersDataChanged")
}

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

/// iCloud 同步状态
enum CloudSyncStatus {
    case available
    case unavailable
    case notDetermined
}

final class PersistenceController: ObservableObject {
    static let shared = PersistenceController()

    /// 持久化存储是否已加载就绪。
    ///
    /// 崩溃修复（2026-10-02）：`loadPersistentStores` 是异步的，且 init 中用信号量最多阻塞
    /// 主线程 5 秒（CloudKit 冷启动 + 弱网时可能超时）。store 未就绪时执行 fetch，
    /// CoreData 抛的是 ObjC `NSException`（如 "Cannot perform operation without a managed
    /// object context" / "could not find an NSEntityDescription"），**Swift 的 try/catch
    /// 捕获不到**，异常直达顶层崩溃。因此所有 fetch 路径必须先检查此标志。
    private(set) var isStoreReady: Bool = false

    /// iCloud 同步状态
    @Published var cloudSyncStatus: CloudSyncStatus = .notDetermined

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

    /// 底层容器。声明为基类 `NSPersistentContainer` 而非
    /// `NSPersistentCloudKitContainer`，以便测试注入仅含 SQLite 存储的普通容器
    /// （迁移验证场景，见 `init(testingWithContainer:)`）。
    /// 生产路径构造的仍是 `NSPersistentCloudKitContainer`（CloudKit 同步所需）。
    let container: NSPersistentContainer

    /// 主上下文访问器。
    ///
    /// 崩溃修复（2026-10-02）：store 未就绪时 fetch 会抛 ObjC `NSException`（Swift 无法捕获）。
    /// 全部 20+ 处 fetch 均写成 `do { try viewContext.fetch } catch { return [] }`，
    /// 看似有兜底实则无效。此处不做拦截（无法在此返回安全的空上下文），
    /// 而是由 `isStoreReady` 供各 Service 主动短路。
    var viewContext: NSManagedObjectContext {
        return container.viewContext
    }

    /// 供 Service 层在 fetch 前调用的就绪守卫。
    /// 未就绪时打印一次并返回 false，调用方应直接返回空结果，避免触发不可捕获的 ObjC 异常。
    func canFetchSafely(_ operation: String = "") -> Bool {
        if isStoreReady { return true }
        if !operation.isEmpty {
            print("⚠️ 跳过 \(operation)：持久化存储尚未就绪")
        }
        return false
    }

    /// 全局共享的 NSManagedObjectModel 实例。
    /// 测试进程中 MockPersistenceController 与真实栈会同时创建容器，若各自按名加载模型，
    /// 会产生两个含同名实体的 NSManagedObjectModel，触发 CoreData
    /// "Failed to find a unique match for an NSEntityDescription" 噪声；共享同一实例可消除。
    static let sharedManagedObjectModel: NSManagedObjectModel = {
        guard let modelURL = Bundle(for: PersistenceController.self).url(forResource: "FlowTakt", withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: modelURL) else {
            fatalError("无法加载 FlowTakt 数据模型")
        }
        return model
    }()

    /// 测试专用初始化器：注入一个已加载完成的外部容器。
    ///
    /// 用途（崩溃修复回归测试 2026-10-02）：`resetDatabase` 依赖
    /// `persistentStoreDescriptions.first?.url` 销毁并重建 store，而测试进程下
    /// `init(inMemory:)` 恒走内存分支（内存 store 的 url 为 nil）。
    /// 验证重置链路必须使用带真实 SQLite 文件 URL 的容器，故提供此入口。
    init(testingWithContainer container: NSPersistentContainer) {
        self.container = container
        isStoreReady = !container.persistentStoreCoordinator.persistentStores.isEmpty
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    init(inMemory: Bool = false) {
        // 检测测试环境：Xcode 运行测试时设置 XCTestConfigurationFilePath 环境变量
        let isTesting = inMemory || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let isCloudSyncEnabled = !isTesting && UserDefaults.standard.bool(forKey: "iCloudSyncEnabled")

        container = NSPersistentCloudKitContainer(name: "FlowTakt", managedObjectModel: Self.sharedManagedObjectModel)

        if isTesting {
            // 测试环境：使用内存存储，避免 CloudKit 依赖
            let description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
            container.persistentStoreDescriptions = [description]
        } else {
            // 配置 CloudKit 同步（仅当用户手动开启后才启用，避免启动即请求网络）
            guard let description = container.persistentStoreDescriptions.first else {
                fatalError("无法获取持久化存储描述")
            }

            if isCloudSyncEnabled {
                // 设置 CloudKit 容器
                description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                    containerIdentifier: "iCloud.com.flowtakt"
                )

                // 启用历史追踪（CloudKit 同步必需）
                description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)

                // 启用远程变更通知（多设备同步）
                description.setOption(true as NSNumber,
                                      forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

                // 观察远程变更
                registerRemoteChangeObserver()
            }
        }

        // 同步加载持久化存储，确保 init 返回前 store 已就绪（避免后续 save() 时 coordinator 为空崩溃）
        // 使用 5 秒超时防止 CloudKit 挂起时死锁；超时后 store 可能仍在异步加载中
        let semaphore = DispatchSemaphore(value: 0)
        container.loadPersistentStores { [weak self] _, error in
            if let error = error as NSError? {
                print("CoreData 加载失败：\(error), \(error.userInfo)")
                // CloudKit 初始化失败时仍可本地使用
            }
            // 仅已启用 CloudKit 时才检查 iCloud 账户
            if isCloudSyncEnabled {
                self?.checkCloudAccountStatus()
            }
            // 崩溃修复（2026-10-02）：仅在真正持有 store 时才标记就绪。
            // 加载失败时 persistentStores 仍为空，若误标为 ready 会让后续 fetch
            // 在无 store 状态下执行并抛出无法被 try/catch 捕获的 ObjC 异常。
            if let self {
                self.isStoreReady = !self.container.persistentStoreCoordinator.persistentStores.isEmpty
            }
            semaphore.signal()
        }
        if semaphore.wait(timeout: .now() + 5) == .timedOut {
            print("⚠️ 持久化存储加载超时（5 秒），store 可能仍在异步加载中")
            // 超时兜底：若此时 store 恰好已就绪则同步标志，否则保持 false 由各 fetch 路径短路
            isStoreReady = !container.persistentStoreCoordinator.persistentStores.isEmpty
        }

        // 冲突合并策略：属性级别的最新写入获胜
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    /// 保存当前上下文
    @discardableResult
    func save() -> Bool {
        let context = container.viewContext
        guard context.hasChanges else { return true }
        // 防御：确保 coordinator 已加载 stores，避免间歇性 "no persistent stores" 崩溃
        guard !container.persistentStoreCoordinator.persistentStores.isEmpty else {
            print("⚠️ save() 跳过：持久化存储尚未就绪")
            return false
        }
        var success = true
        context.performAndWait {
            do {
                // 崩溃修复（2026-10-02）：进入 performAndWait 后再次确认 store 存在。
                // 等待期间可能发生 resetDatabase（会先把 isStoreReady 置 false 并销毁 store），
                // 此时 save 会抛 ObjC 异常且 Swift 无法捕获。
                guard !self.container.persistentStoreCoordinator.persistentStores.isEmpty else {
                    print("⚠️ save() 跳过：持久化存储已不可用")
                    success = false
                    return
                }
                try context.save()
            } catch {
                let nsError = error as NSError
                print("CoreData 保存失败：\(nsError), \(nsError.userInfo)")
                success = false
            }
        }
        return success
    }

    /// 创建后台上下文用于写操作
    func newBackgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        // 自动合并主上下文的变更，避免后台上下文读到过期数据
        context.automaticallyMergesChangesFromParent = true
        return context
    }

    // MARK: - 数据库重置

    /// 重置数据库：销毁当前的所有持久化存储文件并重建空数据库（保留 CloudKit 同步配置）
    /// 三阶段设计：
    /// - Phase 0（调用前）: SettingsView 在调用此方法前先发 databaseWillReset 通知清空 VM 数据
    /// - Phase 1（主线程）: 回滚并 reset viewContext，确保销毁期间没有存活的托管对象
    /// - Phase 2（后台）: 销毁持久化存储（自动清理 SQLite 及 wal/shm 附属文件），避免大库阻塞主线程
    /// - Phase 3（主线程）: 重建描述并加载，随后发 databaseDidReset 通知触发 VM 重新加载
    ///
    /// 线程契约（崩溃审查修复 2026-09-04）：`persistentStoreDescriptions` 赋值与
    /// `loadPersistentStores` 属 NSPersistentContainer 的主线程契约，此前放在后台队列执行属线程违规；
    /// 且销毁期间主线程 viewContext 仍持有对象，CloudKit 远程变更若触发 `refreshAllObjects()`，
    /// 会对已销毁存储的对象触发 fault，抛出 "CoreData could not fulfill a fault" 而崩溃。
    func resetDatabase(completion: @escaping (Bool) -> Void) {
        let coordinator = container.persistentStoreCoordinator

        // 崩溃修复（2026-10-02）：销毁存储期间必须摘除远程变更观察者。
        // 否则 CloudKit 推送会在 Phase 2 的销毁窗口内触发 handleRemoteChange →
        // refreshAllObjects()，对已销毁存储的对象兑现 fault →
        // "CoreData could not fulfill a fault"（NSObjectInaccessibleException）。
        // Phase 3 会在 store 就绪后重新注册。
        NotificationCenter.default.removeObserver(
            self, name: .NSPersistentStoreRemoteChange, object: coordinator)

        // 销毁期间标记为未就绪，短路并发到达的 fetch
        isStoreReady = false

        // Phase 1: 主线程放弃未提交变更并清空上下文。
        // reset() 会移除上下文中全部托管对象，使 Phase 2 销毁存储期间不再有对象
        // 可能因 fault 无法兑现而崩溃。用 performAndWait 确保销毁前已完成。
        container.viewContext.performAndWait {
            container.viewContext.rollback()
            container.viewContext.reset()
        }

        // 在主线程收集待销毁存储的快照（url / type / options），
        // 避免后台队列访问 coordinator.persistentStores 产生竞态
        guard let storeURL = container.persistentStoreDescriptions.first?.url else {
            completion(false)
            return
        }
        let storeSnapshots = coordinator.persistentStores.map {
            (url: $0.url ?? storeURL, type: $0.type, options: $0.options)
        }

        // Phase 2: 后台队列销毁存储文件，避免大库销毁阻塞主线程
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // 销毁所有现有持久化存储；options 传 store 加载时的原始 options（含 CloudKit 配置），
            // 保证 CloudKit store 销毁与加载一致，避免 iCloud 开启时销毁失败
            do {
                for store in storeSnapshots {
                    try coordinator.destroyPersistentStore(at: store.url,
                                                           ofType: store.type,
                                                           options: store.options)
                }
            } catch {
                DispatchQueue.main.async { completion(false) }
                return
            }

            guard let self else {
                DispatchQueue.main.async { completion(false) }
                return
            }

            // Phase 3: 回到主线程重建描述并加载，遵守 NSPersistentContainer 主线程契约
            DispatchQueue.main.async {
                let newDescription = NSPersistentStoreDescription(url: storeURL)
                newDescription.shouldMigrateStoreAutomatically = true
                newDescription.shouldInferMappingModelAutomatically = true

                if UserDefaults.standard.bool(forKey: "iCloudSyncEnabled") {
                    newDescription.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                        containerIdentifier: AppConstants.cloudKitContainerIdentifier
                    )
                    newDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
                    newDescription.setOption(true as NSNumber,
                                             forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
                }

                self.container.persistentStoreDescriptions = [newDescription]

                // loadPersistentStores 内部异步完成加载，不会阻塞主线程
                // 注：此处用强捕获（外层已 `guard let self` 强持有），保持与 completion 生命周期一致
                self.container.loadPersistentStores { _, error in
                    if let error = error as NSError? {
                        print("重置后加载存储失败：\(error), \(error.userInfo)")
                    }
                    if UserDefaults.standard.bool(forKey: "iCloudSyncEnabled") {
                        self.checkCloudAccountStatus()
                        // 崩溃修复（2026-10-02）：重新注册 Phase 1 中摘除的远程变更观察者
                        self.registerRemoteChangeObserver()
                    }

                    // 崩溃修复（2026-10-02）：仅在 store 真正就绪时才发 databaseDidReset。
                    // 该通知会让 6 个 ViewModel 立即同步重查（TimeRecordViewModel 更是直接
                    // loadRecords），若此时 store 尚不可用会触发无法捕获的 CoreData 异常。
                    let ready = !self.container.persistentStoreCoordinator.persistentStores.isEmpty
                    self.isStoreReady = ready

                    self.container.viewContext.reset()
                    guard ready else {
                        print("❌ 重置后 store 未就绪，跳过 databaseDidReset 通知")
                        completion(false)
                        return
                    }
                    NotificationCenter.default.post(name: .databaseDidReset, object: nil)
                    print("✅ 数据库已成功重置：\(storeURL.lastPathComponent)")
                    completion(true)
                }
            }
        }
    }

    // MARK: - CloudKit

    /// 注册远程变更观察者（仅 iCloud 同步开启时需要）。
    /// 崩溃修复（2026-10-02）：抽为独立方法，供 init 与 resetDatabase 的 Phase 3 复用。
    private func registerRemoteChangeObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRemoteChange(_:)),
            name: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator
        )
    }

    /// 处理远程变更通知（其他设备同步数据）
    @objc private func handleRemoteChange(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // 崩溃修复（2026-10-02）：重置数据库期间 isStoreReady 为 false，
            // 此时 store 可能正被销毁，禁止 refreshAllObjects（否则 fault 无法兑现 → 崩溃）。
            guard self.isStoreReady,
                  !self.container.persistentStoreCoordinator.persistentStores.isEmpty else {
                return
            }
            // 先保存未提交的本地编辑，避免 refreshAllObjects() 将其回滚（多设备同步时用户输入静默丢失）
            if self.container.viewContext.hasChanges {
                self.save()
            }
            self.container.viewContext.refreshAllObjects()
        }
    }

    /// 检查 iCloud 账户状态
    private func checkCloudAccountStatus() {
        // 使用显式容器 ID（与 init 配置一致），避免 CKContainer.default() 在多容器 entitlement 下误判
        CKContainer(identifier: AppConstants.cloudKitContainerIdentifier).accountStatus { [weak self] status, error in
            DispatchQueue.main.async {
                switch status {
                case .available:
                    self?.cloudSyncStatus = .available
                    print("✅ iCloud 账户可用，CloudKit 同步已启用")
                case .noAccount, .restricted:
                    self?.cloudSyncStatus = .unavailable
                    print("⚠️ iCloud 账户不可用，数据仅本地存储")
                case .couldNotDetermine, .temporarilyUnavailable:
                    self?.cloudSyncStatus = .unavailable
                    print("⚠️ 无法确定 iCloud 状态")
                @unknown default:
                    self?.cloudSyncStatus = .notDetermined
                }
            }
        }
    }

    /// 手动触发同步（保存主上下文，触发 CloudKit 增量同步）
    func forceSync() {
        print(save() ? "🔄 已手动触发 CloudKit 同步" : "⚠️ 同步跳过：存储未就绪")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

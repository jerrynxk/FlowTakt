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
        task1.storageId = UUID()
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
        task2.storageId = UUID()
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
        session1.storageId = UUID()
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
        session2.storageId = UUID()
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
        achievement1.storageId = UUID()
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
        achievement2.storageId = UUID()
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
        tag.storageId = UUID()
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

    /// 判据收口（唯一处）：当前进程是否处于 XCTest 测试环境。
    ///
    /// Xcode 运行测试时注入 `XCTestConfigurationFilePath` 环境变量。
    /// `init` / `resetDatabase` / `reloadStore` 的 CloudKit 判据必须共用本判据：
    /// 旧实现只有 `init` 带守卫，`resetDatabase` 直接读 UserDefaults，
    /// 导致同进程其它测试类写入 `iCloudSyncEnabled=true` 时，重置用例会真的发
    /// CloudKit 网络请求并因无账号失败——确定性假红，且污染真实网络。
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    // MARK: - iCloud 同步开关判据（判据收口，2026-11-19 用户反馈）

    /// UserDefaults 键（设置页 @AppStorage 与本地判据共用同一键）
    static let iCloudSyncEnabledKey = "iCloudSyncEnabled"

    /// 用户是否开启 iCloud 同步。**默认 true**（自动同步）。
    ///
    /// 用户反馈 2026-11-19：「优先希望实现自动 iCloud 云同步」——同步不应要求用户先去设置里
    /// 手动打开。故首次安装 / 从旧版本升级（该键不存在）一律视为开启；用户显式关闭后尊重选择。
    ///
    /// ⚠️ 必须用 `object(forKey:) as? Bool` 而非 `bool(forKey:)`：后者在键缺失时返回 false，
    /// 无法区分「从未设置」与「用户已关闭」，会把默认值悄悄吞掉。
    /// ⚠️ 禁止在 `init` 里把这个默认值写回 UserDefaults —— 那会在 store 加载窗口内触发
    /// @AppStorage 反向变更通知（历史上导致过并发重载 store 的竞态崩溃）。
    static var isCloudSyncEnabledByUser: Bool {
        UserDefaults.standard.object(forKey: iCloudSyncEnabledKey) as? Bool ?? true
    }

    init(inMemory: Bool = false) {
        // 检测测试环境：Xcode 运行测试时设置 XCTestConfigurationFilePath 环境变量
        let isTesting = inMemory || Self.isRunningTests
        // 2026-10-15：叠加模型兼容性门槛——模型未改造完成前，即使 UserDefaults 开关为 true
        // 也按本地模式启动（开关与门槛的判据都收口在 isCloudKitModelCompatible 一处）
        let isCloudSyncEnabled = !isTesting
            && Self.isCloudSyncEnabledByUser
            && Self.isCloudKitModelCompatible

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
        } else {
            // 修复（2026-10-15 紧急）：iOS 26 SDK 的 NSPersistentCloudKitContainer 在构造时
            // 会**默认启用 CloudKit 集成**（cloudKitContainerOptions 从 entitlements 自动推断），
            // 导致未开启 iCloud 同步的用户也走 CloudKit 校验；模型不满足 CloudKit 规范
            // （非 optional 属性无默认值）时 store 加载直接失败 → isStoreReady=false →
            // 全 App 数据为空（成就/任务/专注统计全空，数据文件为 0 字节）。
            // 用户显式关闭 iCloud 时必须显式清掉这个默认值，恢复「纯本地存储」语义。
            description.cloudKitContainerOptions = nil
            // 门槛拦截后的如实同步（2026-10-15）：UserDefaults 开关为 true 但被模型兼容性
            // 门槛按本地模式启动时，把开关写回 false——设置页 @AppStorage 读到 false，
            // 避免「UI 显示已开启、实际未挂载 CloudKit」的假说明。
            if !isTesting, Self.isCloudSyncEnabledByUser,
               !Self.isCloudKitModelCompatible {
                UserDefaults.standard.set(false, forKey: Self.iCloudSyncEnabledKey)
                print("ℹ️ iCloud 同步开关已自动关闭：数据模型尚未完成 CloudKit 兼容性改造，当前以纯本地模式运行")
            }
        }
        }

        // 同步加载持久化存储，确保 init 返回前 store 已就绪（避免后续 save() 时 coordinator 为空崩溃）
        // 使用 5 秒超时防止 CloudKit 挂起时死锁；超时后 store 可能仍在异步加载中
        //
        // 降级重试（2026-10-15 紧急）：开启 iCloud 同步 + 模型不满足 CloudKit 规范时
        // （错误 134060 "CloudKit integration requires that all attributes be optional..."），
        // store 加载直接失败 → 全 App 静默空数据。此时自动降级为本地存储重试一次：
        // 清掉 CloudKit options（保留 history tracking），用户数据立刻可用；
        // iCloud 同步待模型完成 CloudKit 兼容性改造后再真正启用。
        let semaphore = DispatchSemaphore(value: 0)

        func finalizeLoad(_ error: NSError?) {
            if let error {
                print("CoreData 加载失败：\(error), \(error.userInfo)")
            }
            // 仅当 CloudKit 真正挂载成功时才检查 iCloud 账户
            // （降级模式下 isCloudSyncEnabled 仍为 true，但 options 已清，不该误报账户状态）
            if isCloudSyncEnabled, isCloudKitAttached {
                checkCloudAccountStatus()
            }
            // 崩溃修复（2026-10-02）：仅在真正持有 store 时才标记就绪。
            // 加载失败时 persistentStores 仍为空，若误标为 ready 会让后续 fetch
            // 在无 store 状态下执行并抛出无法被 try/catch 捕获的 ObjC 异常。
            isStoreReady = !container.persistentStoreCoordinator.persistentStores.isEmpty
            semaphore.signal()
        }

        func attemptLoad(allowCloudKitFallback: Bool) {
            container.loadPersistentStores { [weak self] _, error in
                guard let self else {
                    semaphore.signal()
                    return
                }
                let nsError = error as NSError?
                if let nsError, allowCloudKitFallback, isCloudSyncEnabled,
                   nsError.domain == NSCocoaErrorDomain, nsError.code == 134060 {
                    print("⚠️ CloudKit 模型校验失败，自动降级为本地存储模式（iCloud 同步暂不可用，数据不受影响）")
                    // 开关同步回 false：@AppStorage 自动感知，设置页开关如实回弹为关，
                    // 避免「UI 显示已开启、实际未挂载 CloudKit」的假说明
                    UserDefaults.standard.set(false, forKey: Self.iCloudSyncEnabledKey)
                    guard let storeURL = container.persistentStoreDescriptions.first?.url else {
                        finalizeLoad(nsError)
                        return
                    }
                    // 重建 description：无 CloudKit options；history tracking 保留
                    // （store 级持久属性，一旦启用无法关闭）
                    let fallback = Self.makeStoreDescription(at: storeURL, cloudSyncEnabled: false)
                    fallback.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
                    fallback.setOption(true as NSNumber,
                                       forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
                    container.persistentStoreDescriptions = [fallback]
                    attemptLoad(allowCloudKitFallback: false)
                    return
                }
                finalizeLoad(nsError)
            }
        }
        attemptLoad(allowCloudKitFallback: true)

        if semaphore.wait(timeout: .now() + 5) == .timedOut {
            print("⚠️ 持久化存储加载超时（5 秒），store 可能仍在异步加载中")
            // 超时兜底：若此时 store 恰好已就绪则同步标志，否则保持 false 由各 fetch 路径短路
            isStoreReady = !container.persistentStoreCoordinator.persistentStores.isEmpty
        }

        // 冲突合并策略：属性级别的最新写入获胜
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.automaticallyMergesChangesFromParent = true

        #if DEBUG
        // 2026-10-15：开发环境推送 CloudKit schema（首次开启同步的必需步骤——
        // 容器开发环境尚无 schema 时不推送，CloudKit 导入/导出会报
        // "did not find a matching schema" 类错误）。仅 DEBUG + 已挂载 CloudKit 时执行；
        // 异步避免阻塞启动；失败不影响本地使用，下次启动重试。
        if isCloudKitAttached, let cloudContainer = container as? NSPersistentCloudKitContainer {
            Swift.Task.detached(priority: .utility) {
                do {
                    try cloudContainer.initializeCloudKitSchema(options: [])
                    print("☁️ CloudKit schema 已推送到开发环境")
                } catch {
                    print("⚠️ CloudKit schema 推送失败（不影响本地使用）：\(error.localizedDescription)")
                }
            }
        }
        #endif
    }

    /// 保存当前上下文
    @discardableResult
    func save() -> Bool {
        let context = container.viewContext
        var success = true
        context.performAndWait {
            // 修复（2026-10-14 审查 P2-4）：hasChanges 与 store 就绪判断都必须在
            // performAndWait 内做 —— 旧实现先在队列外读 context.hasChanges，
            // 若 save() 被后台线程调用即违反 viewContext 的主队列契约。
            guard context.hasChanges else { return }
            // 防御：确保 coordinator 已加载 stores，避免间歇性 "no persistent stores" 崩溃
            guard !container.persistentStoreCoordinator.persistentStores.isEmpty else {
                print("⚠️ save() 跳过：持久化存储尚未就绪")
                success = false
                return
            }
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

    /// 销毁单个持久化存储，失败时逐级降级并强制清理磁盘残留。
    ///
    /// 修复（2026-10-14，「iCloud 开启时重置数据库失败」）：
    /// 原实现只有一级 `destroyPersistentStore(at:ofType:options: store.options)`，
    /// 任何抛错都直接判定重置失败。iCloud 场景下有三重障碍：
    ///
    /// 1. `store.options` 内含 `NSPersistentCloudKitContainerOptions`，而 CloudKit 镜像
    ///    代理仍持有该 store 引用；带 CloudKit options 调用 `destroyPersistentStore` 会抛错。
    /// 2. 即使传 `nil`，`NSPersistentCloudKitContainer` 仍可能因镜像未拆除而拒绝销毁。
    /// 3. `destroyPersistentStore` 成功时**不删除** `-wal` / `-shm` / `-journal` 附属文件，
    ///    也不删除 CloudKit 的 `.metadata` 目录。残留会导致 Phase 3 重新
    ///    `loadPersistentStores` 时读到旧 WAL/schema 不匹配而加载失败（同样表现为重置失败）。
    ///
    /// 故此处：先摘除 store 引用 → 带 options 销毁 → 传 nil 重试 → 直接删除全部相关文件。
    /// 删除文件是最终兜底，保证 Phase 3 一定能拿到干净的空库。
    nonisolated private static func destroyStore(at url: URL,
                                    ofType type: String,
                                    options: [AnyHashable: Any]?,
                                    coordinator: NSPersistentStoreCoordinator) -> Bool {
        // 先从 coordinator 摘除引用（destroyPersistentStore 失败时这一步能显著提高成功率）
        if let store = coordinator.persistentStores.first(where: { $0.url == url }) {
            try? coordinator.remove(store)
        }

        // 第 1 级：按加载时的原始 options 销毁
        do {
            try coordinator.destroyPersistentStore(at: url, ofType: type, options: options)
        } catch {
            // 第 2 级：传 nil 重试（规避 CloudKit options 导致的销毁失败）
            do {
                try coordinator.destroyPersistentStore(at: url, ofType: type, options: nil)
            } catch {
                print("⚠️ destroyPersistentStore 失败，回退为直接删除文件：\(error.localizedDescription)")
            }
        }

        // 第 3 级：无论上述是否成功，都强制清理磁盘残留
        // （destroyPersistentStore 不删 -wal/-shm，也不删 CloudKit 的 .metadata 目录）
        // 返回值：是否已确认基础 store 文件不存在 —— 修复（2026-10-14 审查 P1-4）
        return removeStoreFiles(at: url)
    }

    /// 删除持久化存储在磁盘上的全部文件：本体 + WAL/SHM/journal + CloudKit `.metadata` 目录。
    ///
    /// `NSPersistentCloudKitContainer` 会在 store 旁生成 `<storeName>.metadata` 目录存放
    /// CloudKit 同步元数据。残留该目录会让重新加载的 store 仍按旧的 record zone 同步，
    /// 甚至直接加载失败，故必须一并删除。
    ///
    /// - Returns: 基础 store 文件是否确认不存在（false = 删除失败，调用方不得报告成功）
    nonisolated private static func removeStoreFiles(at url: URL) -> Bool {
        let fileManager = FileManager.default
        let basePath = url.path

        // 本体与 SQLite 附属文件
        var candidates = [basePath, basePath + "-wal", basePath + "-shm", basePath + "-journal"]
        // CloudKit 元数据目录（目录名形如 FlowTakt.sqlite.metadata）
        let metadataURL = URL(fileURLWithPath: basePath + ".metadata")
        if fileManager.fileExists(atPath: metadataURL.path) {
            candidates.append(metadataURL.path)
        }

        for path in candidates where fileManager.fileExists(atPath: path) {
            do {
                try fileManager.removeItem(atPath: path)
                print("🗑️ 已删除残留文件：\(URL(fileURLWithPath: path).lastPathComponent)")
            } catch {
                print("⚠️ 删除残留文件失败 \(path)：\(error.localizedDescription)")
            }
        }

        // 修复（2026-10-14 审查 P1-4）：三级删除全部失败时旧库仍在磁盘上，
        // 此时重新加载必然「加载成功」→ 若继续报成功就是「假成功」（用户以为清空、实际未动）。
        // 故把落盘结果返回给调用方作为成功判据。
        return !fileManager.fileExists(atPath: basePath)
    }

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
    /// 带失败原因的重置入口，供 UI 精确展示「为什么失败」。
    ///
    /// 修复（2026-10-14）：iCloud 同步开启时，本地 store 重建前先清除 CloudKit 镜像记录
    /// （见 `CloudKitPurgeService`）。时序为**先云端、后本地**：
    /// 云端清除失败即整体中止，本地数据保持原样，避免出现「本地已清、云端仍在，
    /// 下次同步又灌回来」的中间态 —— 用户看到的失败提示必须能说明真实原因。
    ///
    /// 注：不再提供 `Bool` 重载 —— 两个重载会让 `{ _ in }` 这类闭包无法推断类型而编译歧义。
    func resetDatabase(completion: @escaping (Result<Void, Error>) -> Void) {
        // 修复（2026-10-14 审查 P1-5）：并发重入保护。云端清除是异步网络操作（可达数秒），
        // 期间 UI 未阻塞，二次确认会并发触发第二条流程 → 两个流程同时销毁/重载同一 store。
        guard !isResetting else {
            print("⚠️ 重置已在进行中，忽略重复请求")
            // 复审修复（2026-10-14）：SettingsView 在调用前已发过 databaseWillReset，
            // 各 VM 已清空数据。此处早退若不补发 didReset，VM 将永远等不到恢复信号，
            // App 停留在空白页（与 BackupService 失败路径同型缺陷）。
            NotificationCenter.default.post(name: .databaseDidReset, object: nil)
            completion(.failure(LocalResetError.alreadyResetting))
            return
        }
        isResetting = true
        // 所有出口统一经 finish 复位标志，避免标志永久滞留导致后续重置全被拒
        let finish: (Result<Void, Error>) -> Void = { [weak self] result in
            self?.isResetting = false
            completion(result)
        }

        // 测试环境恒走本地分支：与 `init` 的挂载判据保持一致，避免用例间
        // 经 UserDefaults 互相污染后触发真实 CloudKit 请求（详见 isRunningTests）
        let cloudSyncEnabled = !Self.isRunningTests
            && Self.isCloudSyncEnabledByUser
        guard cloudSyncEnabled else {
            performLocalReset(completion: finish)
            return
        }

        NotificationCenter.default.post(name: .databaseWillReset, object: nil)
        CloudKitPurgeService.purgeAll { [weak self] result in
            guard let self else {
                DispatchQueue.main.async { finish(.failure(PurgeAbortError.selfDeallocated)) }
                return
            }
            switch result {
            case .success(let deletedCount):
                print("☁️ 已清除 CloudKit 镜像记录 \(deletedCount) 条，继续重置本地库")
                self.performLocalReset(completion: finish)
            case .failure(let error):
                print("❌ CloudKit 数据清除失败，本地数据未改动：\(error.localizedDescription)")
                // 已发过 databaseWillReset，需让各 VM 重新加载恢复显示
                NotificationCenter.default.post(name: .databaseDidReset, object: nil)
                finish(.failure(error))
            }
        }
    }

    /// 重置进行中标记（防并发重入，见 resetDatabase）
    private var isResetting = false

    /// 仅重置本地 store（不含云端清除）。供 `resetDatabase` 在云端步骤完成后调用。
    private func performLocalReset(completion: @escaping (Result<Void, Error>) -> Void) {
        let coordinator = container.persistentStoreCoordinator

        // 在主线程收集待销毁存储的快照（url / type / options），
        // 避免后台队列访问 coordinator.persistentStores 产生竞态
        let description = container.persistentStoreDescriptions.first
        let storeSnapshots: [(url: URL, type: String, options: [AnyHashable: Any]?)] =
            coordinator.persistentStores.compactMap { store in
                guard let url = store.url ?? description?.url else { return nil }
                return (url: url, type: store.type, options: store.options)
            }

        // 前置校验放在任何状态变更之前（修复 2026-10-14 审查 P2-1）：
        // 旧实现先把 isStoreReady 置 false 并摘除远程观察者，再判内存库/URL 缺失并 return，
        // 导致 store 明明还活着却永久「未就绪」且再也收不到远程变更。
        // 内存 store（仅测试 / SwiftUI 预览使用）没有磁盘文件可重置。
        if storeSnapshots.contains(where: { $0.type == NSInMemoryStoreType })
            || description?.type == NSInMemoryStoreType {
            print("⚠️ 内存 store 无持久化文件，跳过重置")
            completion(.failure(LocalResetError.inMemoryStore))
            return
        }
        guard let storeURL = description?.url else {
            completion(.failure(LocalResetError.storeURLUnavailable))
            return
        }

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

        // Phase 2: 后台队列销毁存储文件，避免大库销毁阻塞主线程
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // 销毁所有现有持久化存储。
            // 修复（2026-10-14）：iCloud 开启时销毁必失败。原实现把 store 加载时的
            // options（含 `NSPersistentCloudKitContainerOptions`）原样回传给
            // `destroyPersistentStore`，而 CloudKit 镜像代理仍持有该 store 的引用，
            // 销毁调用抛错 → 直接 `completion(false)`，用户看到「重置失败」。
            // 现改为三级回退 + 强制清理磁盘残留，见 `destroyStore(at:)`。
            // 收集落盘校验结果（修复 2026-10-14 审查 P1-4）：任一 store 文件仍在磁盘上
            // 就不能报成功，否则就是「报告重置成功但旧数据仍在」的假说明。
            // 复审修复（2026-10-14）：快照为空（store 从未加载成功但磁盘文件仍在）时，
            // 循环一次都不执行 → removalVerified 会保持 true → 旧库被原样加载回来却报
            // 「重置成功」。初值必须表达「确实删过东西」。
            var removalVerified = !storeSnapshots.isEmpty
            for store in storeSnapshots {
                if !Self.destroyStore(at: store.url, ofType: store.type, options: store.options,
                                      coordinator: coordinator) {
                    removalVerified = false
                }
            }

            guard let self else {
                DispatchQueue.main.async { completion(.failure(LocalResetError.selfDeallocated)) }
                return
            }

            // Phase 3: 回到主线程重建描述并加载，遵守 NSPersistentContainer 主线程契约
            DispatchQueue.main.async {
                self.reloadStore(afterResetAt: storeURL, removalVerified: removalVerified,
                                 completion: completion)
            }
        }
    }

    /// 重置后重建 store 描述并加载（`resetDatabase` 的 Phase 3）。
    ///
    /// 修复（2026-10-14）：iCloud 开启时，即使旧 store 已成功销毁，带 CloudKit 选项的
    /// 重新加载仍可能失败（容器未在 App Store Connect 部署 schema、账户不可用、
    /// 或重置后 `.metadata` 同步状态与新库不一致）。原实现此时直接 `completion(false)`，
    /// 用户不仅看到「重置失败」，还会残留一个已销毁的旧 store —— App 处于无库可用状态。
    ///
    /// 现改为：CloudKit 加载失败时**自动降级为纯本地 store** 并视重置成功。
    /// 用户数据确实已被清空（重置的语义已达成），App 立即恢复可用；
    /// iCloud 会在下次冷启动按 `iCloudSyncEnabled` 重新尝试挂载 CloudKit。
    private func reloadStore(afterResetAt storeURL: URL,
                             removalVerified: Bool = true,
                             completion: @escaping (Result<Void, Error>) -> Void,
                             allowCloudKit: Bool? = nil) {
        // 显式 allowCloudKit（用户切换开关）优先；隐式回落同样受测试环境守卫，
        // 判据与 `init` 一致（见 isRunningTests）
        let cloudSyncEnabled = allowCloudKit
            ?? (!Self.isRunningTests && Self.isCloudSyncEnabledByUser)
        let description = Self.makeStoreDescription(at: storeURL, cloudSyncEnabled: cloudSyncEnabled)
        container.persistentStoreDescriptions = [description]

        // loadPersistentStores 内部异步完成加载，不会阻塞主线程
        container.loadPersistentStores { [weak self] _, error in
            guard let self else { return }
            if let error = error as NSError? {
                print("重置后加载存储失败：\(error), \(error.userInfo)")
            }

            let loaded = !self.container.persistentStoreCoordinator.persistentStores.isEmpty
            if !loaded && cloudSyncEnabled {
                print("⚠️ CloudKit 加载失败，降级为本地 store（下次冷启动将重试挂载 CloudKit）")
                // 显式传 false，避免回退时再次读到 UserDefaults 的 true 造成无限递归
                self.reloadStore(afterResetAt: storeURL, removalVerified: removalVerified,
                                 completion: completion, allowCloudKit: false)
                return
            }

            if cloudSyncEnabled && loaded {
                self.checkCloudAccountStatus()
                // 崩溃修复（2026-10-02）：重新注册 Phase 1 中摘除的远程变更观察者
                self.registerRemoteChangeObserver()
            }

            // 崩溃修复（2026-10-02）：仅在 store 真正就绪时才发 databaseDidReset。
            // 该通知会让 6 个 ViewModel 立即同步重查（TimeRecordViewModel 更是直接
            // loadRecords），若此时 store 尚不可用会触发无法捕获的 CoreData 异常。
            self.isStoreReady = loaded
            self.container.viewContext.reset()

            guard loaded else {
                print("❌ 重置后 store 未就绪，跳过 databaseDidReset 通知")
                completion(.failure(LocalResetError.storeReloadFailed))
                return
            }
            NotificationCenter.default.post(name: .databaseDidReset, object: nil)
            // 落盘校验（修复 2026-10-14 审查 P1-4）：文件删不掉时旧库会被原样加载回来，
            // 此时数据其实没被清掉 —— 必须报失败并说明原因，不能弹「重置成功」。
            guard removalVerified else {
                print("❌ 旧 store 文件仍存在于磁盘，重置未生效")
                completion(.failure(LocalResetError.storeRemovalFailed))
                return
            }
            print("✅ 数据库已成功重置：\(storeURL.lastPathComponent)")
            completion(.success(()))
        }
    }

    /// 本地重置流程的失败原因（供 UI 精确展示，禁止笼统报「重置失败」）。
    /// 修复（2026-10-14 审查 P2-5）：原先 4 个 case 共用同一句「数据库重置失败」，
    /// 用户无法判断到底哪里出错——这正是「假说明」。现按 case 给差异文案。
    enum LocalResetError: LocalizedError {
        case inMemoryStore
        case storeURLUnavailable
        case storeReloadFailed
        case storeRemovalFailed
        case alreadyResetting
        case selfDeallocated
        case cloudKitModelNotCompatible

        var errorDescription: String? {
            switch self {
            case .inMemoryStore:
                return L10n.shared.重置失败原因内存库
            case .storeURLUnavailable:
                return L10n.shared.重置失败原因路径缺失
            case .storeReloadFailed:
                return L10n.shared.重置失败原因重载失败
            case .storeRemovalFailed:
                return L10n.shared.重置失败原因删除失败
            case .alreadyResetting:
                return L10n.shared.重置进行中
            case .selfDeallocated:
                return L10n.shared.重置失败原因已中止
            case .cloudKitModelNotCompatible:
                return L10n.shared.iCloud模型未兼容
            }
        }
    }

    /// 云端清除阶段的失败原因。
    enum PurgeAbortError: LocalizedError {
        case selfDeallocated
        var errorDescription: String? { L10n.shared.重置失败原因已中止 }
    }

    /// 构建 store 描述（`init` 与重置后重建共用，确保两条路径的 CloudKit 配置完全一致）。
    private static func makeStoreDescription(at url: URL,
                                             cloudSyncEnabled: Bool) -> NSPersistentStoreDescription {
        let description = NSPersistentStoreDescription(url: url)
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        if cloudSyncEnabled {
            description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: AppConstants.cloudKitContainerIdentifier
            )
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description.setOption(true as NSNumber,
                                  forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        }
        return description
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
    /// - Parameter completion: 状态快照更新完成后回调（主队列），供调用方随后执行依赖最新状态的逻辑
    private func checkCloudAccountStatus(completion: (() -> Void)? = nil) {
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
                completion?()
            }
        }
    }

    /// 公开包装：刷新 iCloud 账户状态快照（2026-11-19 修复）。
    ///
    /// 旧实现 `cloudSyncStatus` 只在 store 加载成功时设置一次，之后永不刷新：
    /// 用户在登出状态下启动 App → 快照停留 `.unavailable` → 重新登录 iCloud 后
    /// 不重启 App，手动同步恒报「账户不可用」（用户反馈：立即同步无效）。
    /// 供 SyncService 在 `CKAccountChanged` 与手动同步前调用。
    func refreshCloudAccountStatus(completion: (() -> Void)? = nil) {
        checkCloudAccountStatus(completion: completion)
    }

    /// 运行时切换 iCloud 同步挂载（2026-10-15 审查 P0-1）。
    ///
    /// 问题背景：`init` 只在启动时读一次 `iCloudSyncEnabled`，用户在设置页开关后
    /// 仅写 UserDefaults，CloudKit 选项并未挂载/卸载——开关形同虚设，
    /// `forceSync` 的「CloudKit 将在后台推送」文案也会构成误导。
    ///
    /// 实现：卸载现有 store（**不删文件，数据保留**，与 resetDatabase 的根本区别），
    /// 按 `enabled` 重建 store 描述并重新加载。复用 `reloadStore` 的加载/降级/
    /// 观察者注册/`databaseDidReset` 通知链路（VM 收到通知后重查，旧对象引用随
    /// `viewContext.reset()` 一并失效，与重置窗口的防护语义一致）。
    ///
    /// - Note: 历史追踪（`NSPersistentHistoryTrackingKey`）是 store 级持久属性，
    ///   一旦启用便无法关闭；关闭 CloudKit 时必须继续设置，否则重新加载报错。
    func applyCloudKitConfiguration(enabled: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        // 模型兼容性门槛（2026-10-15）：模型未改造完成前拒绝挂载 CloudKit——
        // 挂载必失败（134060）且会与本地降级重载竞态导致崩溃。如实拒绝，不动 store。
        if enabled && !Self.isCloudKitModelCompatible {
            print("⚠️ 拒绝挂载 CloudKit：数据模型尚未完成兼容性改造（isCloudKitModelCompatible=false）")
            DispatchQueue.main.async {
                completion(.failure(LocalResetError.cloudKitModelNotCompatible))
            }
            return
        }
        guard let storeURL = container.persistentStoreDescriptions.first?.url else {
            completion(.failure(LocalResetError.storeURLUnavailable))
            return
        }
        // 重载窗口期禁 fetch（与重置流程同一守卫语义）
        isStoreReady = false
        // 卸载现有 store（数据仍在磁盘）
        for store in container.persistentStoreCoordinator.persistentStores {
            do {
                try container.persistentStoreCoordinator.remove(store)
            } catch {
                print("⚠️ 卸载 store 失败：\(error.localizedDescription)")
            }
        }
        container.viewContext.reset()

        let description = Self.makeStoreDescription(at: storeURL, cloudSyncEnabled: enabled)
        if !enabled {
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description.setOption(true as NSNumber,
                                  forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        }
        container.persistentStoreDescriptions = [description]

        // 重新加载（loadPersistentStores 异步完成，completion 在加载回调线程触发）
        container.loadPersistentStores { [weak self] _, error in
            guard let self else { return }
            if let error = error as NSError? {
                print("切换 iCloud 同步后加载存储失败：\(error), \(error.userInfo)")
            }
            let loaded = !self.container.persistentStoreCoordinator.persistentStores.isEmpty
            self.isStoreReady = loaded
            if loaded {
                if enabled {
                    self.checkCloudAccountStatus()
                    self.registerRemoteChangeObserver()
                }
                self.container.viewContext.reset()
                // 让全部 ViewModel 重查（store 已是新实例，旧 NSManagedObject 引用失效）
                NotificationCenter.default.post(name: .databaseDidReset, object: nil)
                print(enabled ? "✅ iCloud 同步已挂载（运行时生效）" : "✅ iCloud 同步已卸载（运行时生效，数据保留在本地）")
                DispatchQueue.main.async { completion(.success(())) }
            } else if enabled {
                // 修复（2026-11-19 用户反馈「重新登录后数据被吃掉」）：旧实现失败分支
                // 让 store 保持卸载态、isStoreReady=false、无任何重试 —— 全部 Service 经
                // canFetchSafely 短路返回空，全 App 呈现「数据全没了」的假象（文件其实还在磁盘）。
                // 兜底：用本地模式 description 重载一次，保证数据始终可用；同步如实报失败。
                print("⚠️ CloudKit 模式重载失败，降级为本地模式重载（数据保留在磁盘）")
                let fallback = Self.makeStoreDescription(at: storeURL, cloudSyncEnabled: false)
                // 历史追踪是 store 级持久属性，一旦启用无法关闭，重载必须继续设置
                fallback.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
                fallback.setOption(true as NSNumber,
                                   forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
                self.container.persistentStoreDescriptions = [fallback]
                self.container.loadPersistentStores { [weak self] _, fallbackError in
                    guard let self else { return }
                    if let fallbackError = fallbackError as NSError? {
                        print("⚠️ 本地模式兜底重载也失败：\(fallbackError), \(fallbackError.userInfo)")
                    }
                    let loaded = !self.container.persistentStoreCoordinator.persistentStores.isEmpty
                    self.isStoreReady = loaded
                    if loaded {
                        self.container.viewContext.reset()
                        NotificationCenter.default.post(name: .databaseDidReset, object: nil)
                        print("✅ 已降级为本地模式（数据可用；iCloud 同步未开启）")
                    }
                    // 仍如实上报失败：UI 回滚开关 —— 「数据已保住」不等于「同步已开启」
                    DispatchQueue.main.async { completion(.failure(LocalResetError.storeReloadFailed)) }
                }
            } else {
                DispatchQueue.main.async { completion(.failure(LocalResetError.storeReloadFailed)) }
            }
        }
    }

    /// CloudKit 是否已实际挂载到当前 store（区别于 UserDefaults 里的开关值）。
    /// 供 forceSync 与设置页如实反馈「已启用」vs「待重启生效」。
    var isCloudKitAttached: Bool {
        container.persistentStoreDescriptions.first?.cloudKitContainerOptions != nil
    }

    /// CloudKit 模型兼容性门槛（2026-10-15 判据收口处）。
    ///
    /// **2026-10-15 晚：模型已完成兼容性改造**——全部 32 个非 optional 属性补默认值
    /// （Date/UUID/String/Boolean），关系本就全 optional + inverse，无 unique 约束，
    /// 通过 CloudKit 校验。置 true 放开 iCloud 同步。
    /// 若未来模型改动触发校验失败，降级逻辑仍会兜底为本地模式（数据不受影响）。
    static let isCloudKitModelCompatible = true

    /// 手动触发同步（保存主上下文，触发 CloudKit 增量导出）。
    ///
    /// 用户反馈 2026-11-17：旧实现只 print 日志、UI 却无条件显示「同步请求已发送」，
    /// 属"假说明"。现返回真实结果供 UI 如实反馈。
    ///
    /// 重要语义澄清（避免再次误导用户）：
    /// - 本方法只有**导出**能力（保存本地变更 → CloudKit 后台推送）。
    /// - NSPersistentCloudKitContainer 没有公开的"强制从云端拉取"API；其它设备的更新
    ///   由系统静默推送 / App 回到前台时自动导入。因此 `noLocalChanges` 时必须如实告知，
    ///   不能谎称"已同步"。
    @discardableResult
    func forceSync() -> SyncOutcome {
        guard canFetchSafely("手动同步") else {
            print("⚠️ 同步跳过：本地数据尚未就绪")
            return .failed("本地数据尚未就绪")
        }
        let syncEnabled = Self.isCloudSyncEnabledByUser
        guard syncEnabled else {
            print("⚠️ iCloud 同步开关未开启")
            return .syncDisabled
        }
        guard cloudSyncStatus == .available else {
            print("⚠️ iCloud 账户不可用：\(cloudSyncStatus)")
            return .accountUnavailable
        }
        guard isCloudKitAttached else {
            print("⚠️ 同步开关已开但 store 未挂载 CloudKit")
            return .notMounted
        }
        guard container.viewContext.hasChanges else {
            print("ℹ️ 无本地变更；其它设备的更新会由系统在后台推送 / 回到前台时导入")
            return .noLocalChanges
        }
        let ok = save()
        print(ok ? "🔄 已保存本地变更，CloudKit 将在后台推送" : "⚠️ 同步失败：保存未成功")
        return ok ? .savedLocalChanges : .failed("本地保存失败，请稍后重试")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

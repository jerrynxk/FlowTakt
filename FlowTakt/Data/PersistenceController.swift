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

    let container: NSPersistentCloudKitContainer

    var viewContext: NSManagedObjectContext {
        return container.viewContext
    }

    init(inMemory: Bool = false) {
        // 检测测试环境：Xcode 运行测试时设置 XCTestConfigurationFilePath 环境变量
        let isTesting = inMemory || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let isCloudSyncEnabled = !isTesting && UserDefaults.standard.bool(forKey: "iCloudSyncEnabled")

        container = NSPersistentCloudKitContainer(name: "FlowTakt")

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
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(handleRemoteChange(_:)),
                    name: .NSPersistentStoreRemoteChange,
                    object: container.persistentStoreCoordinator
                )
            }
        }

        // 同步加载持久化存储，确保 init 返回前 store 已就绪（避免后续 save() 时 coordinator 为空崩溃）
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
            semaphore.signal()
        }
        semaphore.wait()

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
    /// 两阶段设计：
    /// - Phase 0（调用前）: SettingsView 在调用此方法前先发 databaseWillReset 通知清空 VM 数据
    /// - Phase 1: 销毁持久化存储（自动清理 SQLite 及 wal/shm 附属文件）
    /// - Phase 2: 重新创建一个带 CloudKit 配置的全新空存储
    /// - Phase 3: 发送 databaseDidReset 通知触发 VM 重新加载
    /// - Throws: 重置过程中的错误
    func resetDatabase() throws {
        let coordinator = container.persistentStoreCoordinator

        // 在主上下文线程中执行
        try container.viewContext.performAndWait {
            let context = container.viewContext

            // 1. 放弃未提交的变更
            context.rollback()

            // 2. 获取当前存储的 URL
            guard let storeURL = container.persistentStoreDescriptions.first?.url else {
                throw PersistenceError.storeURLNotFound
            }

            // 3. 销毁所有现有持久化存储（destroy 会自动删除 SQLite + wal + shm 文件）
            for store in coordinator.persistentStores {
                try coordinator.destroyPersistentStore(at: store.url ?? storeURL,
                                                       ofType: store.type,
                                                       options: nil)
            }

            // 4. 重建持久化存储描述
            let newDescription = NSPersistentStoreDescription(url: storeURL)
            newDescription.shouldMigrateStoreAutomatically = true
            newDescription.shouldInferMappingModelAutomatically = true

            // 重新配置 CloudKit 同步（与 init 中保持一致，仅当用户已开启同步）
            if UserDefaults.standard.bool(forKey: "iCloudSyncEnabled") {
                newDescription.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                    containerIdentifier: AppConstants.cloudKitContainerIdentifier
                )
                newDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
                newDescription.setOption(true as NSNumber,
                                         forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            }

            // 替换容器描述并重新加载（同步等待，确保 store 就绪后再返回）
            container.persistentStoreDescriptions = [newDescription]

            let resetSemaphore = DispatchSemaphore(value: 0)
            container.loadPersistentStores { [weak self] _, error in
                if let error = error as NSError? {
                    print("重置后加载存储失败：\(error), \(error.userInfo)")
                }
                if UserDefaults.standard.bool(forKey: "iCloudSyncEnabled") {
                    self?.checkCloudAccountStatus()
                }
                resetSemaphore.signal()
            }
            resetSemaphore.wait()

            // 5. 重置上下文
            context.reset()

            print("✅ 数据库已成功重置：\(storeURL.lastPathComponent)")
        }

        // 通知所有 ViewModel 重新加载数据
        NotificationCenter.default.post(name: .databaseDidReset, object: nil)
    }

    // MARK: - CloudKit

    /// 处理远程变更通知（其他设备同步数据）
    @objc private func handleRemoteChange(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.container.viewContext.refreshAllObjects()
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

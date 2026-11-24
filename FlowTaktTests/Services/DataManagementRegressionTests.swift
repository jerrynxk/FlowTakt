import XCTest
import CoreData
@testable import FlowTakt

// MARK: - DataManagementRegressionTests
// 修复（2026-10-14）：用户报告的三个数据管理功能失败
//
// 1. iCloud 同步开启时「重置数据库」提示重置失败
//    根因：resetDatabase 把 store 加载时的原始 options（含 NSPersistentCloudKitContainerOptions）
//    回传给 destroyPersistentStore，CloudKit 镜像仍持有 store 引用 → 抛错 → 直接返回 false。
//    修复：三级回退销毁 + 强制清理 -wal/-shm/.metadata 残留 + 加载失败降级为本地 store。
//
// 2. 「导出数据」提示导出失败
//    根因：exportAll 无 store 就绪守卫，冷启动 CloudKit 加载未完成时后台 fetch 抛错，
//    三类导出各返回 nil → urls.isEmpty → UI 误报失败（实为「无数据」或「未就绪」）。
//    修复：引入 ExportResult 区分 success/noData/storeNotReady/failed + 可注入持久化控制器。
//
// 3. 「恢复数据」提示恢复失败
//    根因：fileImporter 返回 security-scoped URL，未调用 startAccessingSecurityScopedResource()
//    时真机读取抛 NSCocoaErrorDomain Code=257，被 catch 吞掉后返回 false。
//    修复：SettingsView 中成对 start/stop 安全作用域访问。

@MainActor
final class DataManagementRegressionTests: XCTestCase {

    private var persistence: PersistenceController!
    private var taskService: TaskServiceProtocol!
    private var backupService: BackupService!

    override func setUp() {
        super.setUp()
        persistence = PersistenceController(inMemory: true)
        taskService = TaskService(persistenceController: persistence)
        backupService = BackupService(persistenceController: persistence)
    }

    override func tearDown() {
        backupService = nil
        taskService = nil
        persistence = nil
        super.tearDown()
    }

    /// 造一条任务（TaskService 的必填参数较多，统一在此构造）
    @discardableResult
    private func makeTask(_ title: String) -> Task {
        taskService.createTask(title: title, notes: nil, estimatedPomodoros: 2,
                               priority: 2, dueDate: nil, recurrenceRule: nil)
    }

    // ========================================================================
    // MARK: - 1. 重置数据库
    // ========================================================================

    /// 构造文件型 store（resetDatabase 依赖 persistentStoreDescriptions.first?.url，
    /// 内存 store 的 url 为 nil 会命中 guard 提前返回）。
    private func makeFileStorePersistence() throws -> (PersistenceController, URL) {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dm_regression_\(UUID().uuidString).sqlite")
        let description = NSPersistentStoreDescription(url: storeURL)
        description.type = NSSQLiteStoreType
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true

        let container = NSPersistentCloudKitContainer(
            name: "FlowTakt",
            managedObjectModel: PersistenceController.sharedManagedObjectModel
        )
        container.persistentStoreDescriptions = [description]

        let sem = DispatchSemaphore(value: 0)
        container.loadPersistentStores { _, error in
            if let error = error { print("测试栈加载失败：\(error)") }
            sem.signal()
        }
        XCTAssertEqual(sem.wait(timeout: .now() + 10), .success, "测试栈应在 10 秒内加载完成")
        return (PersistenceController(testingWithContainer: container), storeURL)
    }

    /// 清理 store 及其附属文件
    private func cleanUp(_ storeURL: URL) {
        let fm = FileManager.default
        for suffix in ["", "-wal", "-shm", "-journal", ".metadata"] {
            try? fm.removeItem(atPath: storeURL.path + suffix)
        }
    }

    /// 重置数据库必须能扛住磁盘残留：`-wal` / `-shm` 内容损坏 + CloudKit `.metadata` 目录残留。
    /// 原实现即使 destroyPersistentStore 成功也不删这些文件，Phase 3 重新加载会失败 → 表现为「重置失败」。
    ///
    /// 注意：断言用 `.metadata` 目录而非 `-wal`/`-shm` —— 新 store 加载后 SQLite 会
    /// 重新生成 `-wal`/`-shm`，它们的存在与否不能作为残留是否清理的判据；
    /// 而 `.metadata` 只有 CloudKit store 才会创建，本地 store 不会重建，可稳定断言。
    func testResetDatabase_WithCorruptResidue_ThenSucceedsAndClearsMetadata() throws {
        let (filePersistence, storeURL) = try makeFileStorePersistence()
        defer { cleanUp(storeURL) }

        // Given：库中已有数据，且磁盘上存在损坏的 WAL/SHM 与 CloudKit 元数据残留
        let service = TaskService(persistenceController: filePersistence)
        _ = service.createTask(title: "将被清空", notes: nil, estimatedPomodoros: 2,
                               priority: 2, dueDate: nil, recurrenceRule: nil)
        XCTAssertTrue(filePersistence.isStoreReady)

        let fm = FileManager.default
        try Data("corrupt-residue".utf8).write(to: URL(fileURLWithPath: storeURL.path + "-wal"))
        try Data("corrupt-residue".utf8).write(to: URL(fileURLWithPath: storeURL.path + "-shm"))
        let metadataPath = storeURL.path + ".metadata"
        try fm.createDirectory(atPath: metadataPath, withIntermediateDirectories: true)
        try Data("stale-zone".utf8).write(to: URL(fileURLWithPath: metadataPath + "/zone.json"))
        XCTAssertTrue(fm.fileExists(atPath: metadataPath), "前置：.metadata 残留应存在")

        let exp = expectation(forNotification: .databaseDidReset, object: nil)
        var completed: Bool?

        // When
        filePersistence.resetDatabase { completed = (try? $0.get()) != nil }

        // Then：重置成功，CloudKit 元数据残留被清除，库可继续写入
        wait(for: [exp], timeout: 20.0)
        XCTAssertEqual(completed, true, "存在磁盘残留时重置仍应成功")
        XCTAssertFalse(fm.fileExists(atPath: metadataPath), "CloudKit .metadata 残留应被清除")
        XCTAssertTrue(filePersistence.isStoreReady, "重置后 store 应重新就绪")
        XCTAssertTrue(service.fetchAllTasks().isEmpty, "重置后数据应被清空")
        XCTAssertNoThrow(service.createTask(title: "重置后新建", notes: nil, estimatedPomodoros: 2,
                                            priority: 2, dueDate: nil, recurrenceRule: nil),
                         "重置后应可继续写入")
    }

    /// 重置后数据应真正清空，且可继续写入（验证重建出的 store 干净可用）。
    func testResetDatabase_ThenDataClearedAndWritable() throws {
        let (filePersistence, storeURL) = try makeFileStorePersistence()
        defer { cleanUp(storeURL) }

        let service = TaskService(persistenceController: filePersistence)
        _ = service.createTask(title: "待清空任务", notes: nil, estimatedPomodoros: 2,
                               priority: 2, dueDate: nil, recurrenceRule: nil)
        XCTAssertFalse(service.fetchAllTasks().isEmpty)

        let exp = expectation(forNotification: .databaseDidReset, object: nil)
        filePersistence.resetDatabase { _ in }
        wait(for: [exp], timeout: 20.0)

        XCTAssertTrue(service.fetchAllTasks().isEmpty, "重置后任务应被清空")
        XCTAssertNoThrow(service.createTask(title: "重置后新建", notes: nil, estimatedPomodoros: 2,
                                            priority: 2, dueDate: nil, recurrenceRule: nil),
                         "重置后应可继续写入")
    }

    /// 内存 store 无 URL 时应安全返回 false，不崩溃、不挂起。
    func testResetDatabase_WithInMemoryStore_ReturnsFalseSafely() {
        let exp = expectation(description: "resetDatabase 回调")
        var result: Bool?
        persistence.resetDatabase { outcome in
            // 内存 store 无持久化文件，契约上必须返回 failure
            if case .failure = outcome { result = false }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 10.0)
        XCTAssertEqual(result, false, "内存 store 无 URL 时应安全返回 false")
    }

    // ========================================================================
    // MARK: - 2. 导出数据
    // ========================================================================

    /// 有数据时应返回 .success 且产出 CSV 文件（而非误报失败）。
    func testExportAll_WithData_ThenReturnsSuccessWithFiles() throws {
        // Given：库中存在任务数据
        _ = makeTask("导出任务")
        persistence.save()

        let exp = expectation(description: "导出回调")
        var result: ExportResult?

        // When
        DataExportService.exportAll(using: persistence) {
            result = $0
            exp.fulfill()
        }
        wait(for: [exp], timeout: 10.0)

        // Then
        let unwrapped = try XCTUnwrap(result)
        guard case .success(let urls) = unwrapped else {
            return XCTFail("有数据时应导出成功，实际：\(unwrapped)")
        }
        XCTAssertFalse(urls.isEmpty, "应至少产出一份 CSV")
        for url in urls {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "CSV 文件应存在")
        }
    }

    /// 空库应返回 .noData 而**不是** .failed —— 这是原实现误报「导出失败」的场景之一。
    func testExportAll_WithEmptyStore_ThenReturnsNoDataNotFailed() throws {
        let exp = expectation(description: "导出回调")
        var result: ExportResult?

        DataExportService.exportAll(using: persistence) {
            result = $0
            exp.fulfill()
        }
        wait(for: [exp], timeout: 10.0)

        let unwrapped = try XCTUnwrap(result)
        guard case .noData = unwrapped else {
            return XCTFail("空库应返回 .noData，实际：\(unwrapped)")
        }
    }

    /// store 未就绪时应返回 .storeNotReady —— 防止后台 context 在无 store 时 fetch 触发崩溃。
    func testExportAll_WithStoreNotReady_ThenReturnsStoreNotReady() throws {
        // 构造一个没有任何 store 的控制器，模拟「加载未完成」
        let emptyContainer = NSPersistentContainer(
            name: "FlowTakt",
            managedObjectModel: PersistenceController.sharedManagedObjectModel
        )
        let notReady = PersistenceController(testingWithContainer: emptyContainer)
        XCTAssertFalse(notReady.isStoreReady, "前置：该容器不应有 store")

        let exp = expectation(description: "导出回调")
        var result: ExportResult?

        DataExportService.exportAll(using: notReady) {
            result = $0
            exp.fulfill()
        }
        wait(for: [exp], timeout: 10.0)

        let unwrapped = try XCTUnwrap(result)
        guard case .storeNotReady = unwrapped else {
            return XCTFail("store 未就绪应返回 .storeNotReady，实际：\(unwrapped)")
        }
    }

    /// 只有习惯数据（无任务/会话/打卡）时也应导出成功。
    /// 原实现只导出 3 类实体，这类用户会得到空结果 → 旧代码误报「导出失败」。
    func testExportAll_WithOnlyHabits_ThenStillExports() throws {
        let habitService = HabitService(persistenceController: persistence)
        _ = habitService.createHabit(name: "喝水", descriptionText: nil,
                                     iconName: "drop", colorHex: "#007AFF",
                                     frequency: "daily", targetCount: 8)
        persistence.save()

        let exp = expectation(description: "导出回调")
        var result: ExportResult?
        DataExportService.exportAll(using: persistence) {
            result = $0
            exp.fulfill()
        }
        wait(for: [exp], timeout: 10.0)

        let unwrapped = try XCTUnwrap(result)
        guard case .success(let urls) = unwrapped else {
            return XCTFail("仅有习惯数据时也应导出成功，实际：\(unwrapped)")
        }
        XCTAssertTrue(urls.contains { $0.lastPathComponent == "flowtakt_habits.csv" },
                      "应产出习惯 CSV，实际文件：\(urls.map(\.lastPathComponent))")
    }

    // ========================================================================
    // MARK: - 3. 备份 / 恢复往返
    // ========================================================================

    /// 备份 → 恢复往返：数据应完整还原（覆盖式恢复，不产生重复）。
    func testBackupThenRestore_RoundTrip_RestoresData() async throws {
        _ = makeTask("备份任务")
        persistence.save()

        let backupURLExported = await backupService.exportJSONAsync()
        let backupURL = try XCTUnwrap(backupURLExported, "应成功导出备份")
        defer { try? FileManager.default.removeItem(at: backupURL) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path))

        let restored = backupService.importJSON(from: backupURL)

        XCTAssertTrue(restored, "恢复应成功")
        let tasks = taskService.fetchAllTasks()
        XCTAssertEqual(tasks.count, 1, "恢复后任务应为 1（清空生效，未重复）")
        XCTAssertEqual(tasks.first?.title, "备份任务")
    }

    /// 导出的备份文件必须能被重新读取，且 ISO8601 日期可被同一 decoder 解码。
    func testExportedBackup_IsDecodableBySameDecoder() async throws {
        _ = makeTask("解码验证")
        persistence.save()

        let backupURLExported = await backupService.exportJSONAsync()
        let backupURL = try XCTUnwrap(backupURLExported)
        defer { try? FileManager.default.removeItem(at: backupURL) }

        let data = try Data(contentsOf: backupURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(BackupPayload.self, from: data)

        XCTAssertEqual(payload.version, BackupPayload.currentVersion)
        XCTAssertEqual(payload.tasks.count, 1)
        XCTAssertEqual(payload.tasks.first?.title, "解码验证")
    }

    /// 非法文件应被拒绝且**不破坏现有数据**。
    func testImportJSON_InvalidFile_ThenRejectedAndDataPreserved() throws {
        _ = makeTask("原有任务")
        persistence.save()
        let originalCount = taskService.fetchAllTasks().count
        XCTAssertGreaterThan(originalCount, 0)

        let badURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("invalid_\(UUID().uuidString).json")
        try "not json at all".write(to: badURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: badURL) }

        XCTAssertFalse(backupService.importJSON(from: badURL), "非法文件应恢复失败")
        XCTAssertEqual(taskService.fetchAllTasks().count, originalCount,
                       "拒绝恢复时原有数据必须完好")
    }

    /// 不存在的文件应返回 false 而不崩溃（对应真机上「文件不可访问」的场景）。
    func testImportJSON_NonexistentFile_ThenReturnsFalseSafely() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("does_not_exist_\(UUID().uuidString).json")
        XCTAssertFalse(backupService.importJSON(from: missing), "文件不存在应返回 false")
    }
}

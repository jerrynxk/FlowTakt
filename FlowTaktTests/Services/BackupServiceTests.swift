import XCTest
import CoreData
@testable import FlowTakt

// MARK: - BackupServiceTests（B4：JSON 导出 → 恢复往返）

@MainActor
final class BackupServiceTests: XCTestCase {
    var persistence: PersistenceController!
    var service: BackupService!

    override func setUp() {
        super.setUp()
        persistence = PersistenceController(inMemory: true)
        service = BackupService(persistenceController: persistence)
    }

    override func tearDown() {
        service = nil
        persistence = nil
        super.tearDown()
    }

    private func seedData() {
        let context = persistence.viewContext
        let task = Task(context: context)
        task.storageId = UUID()
        task.title = "备份任务"
        task.status = TaskStatus.active.rawValue
        task.estimatedPomodoros = 2
        task.completedPomodoros = 0
        task.priority = 3
        task.displayOrder = 0
        task.createdAt = Date()
        task.updatedAt = Date()

        let session = FocusSession(context: context)
        session.storageId = UUID()
        session.startTime = Date()
        session.plannedDuration = 1500
        session.actualDuration = 1500
        session.status = SessionStatus.completed.rawValue
        session.phase = FocusPhase.focus.rawValue
        session.earnedPoints = 10
        session.roundIndex = 1
        session.task = task
        session.createdAt = Date()
        session.updatedAt = Date()
        try? context.save()
    }

    func testExportJSON_ThenProducesFile() async throws {
        // Given
        seedData()

        // When
        let url = await service.exportJSONAsync()

        // Then
        let fileURL = try XCTUnwrap(url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path), "导出应生成文件")
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(BackupPayload.self, from: data)
        XCTAssertEqual(payload.tasks.count, 1)
        XCTAssertEqual(payload.focusSessions.count, 1)
        XCTAssertNotNil(payload.tags, "导出应包含 tags")
        XCTAssertEqual(payload.tasks.first?.title, "备份任务")
        XCTAssertEqual(payload.focusSessions.first?.status, SessionStatus.completed.rawValue)
    }

    func testExportThenImport_RoundTrip_RestoresData() async throws {
        // Given - 先导出（库中已有 1 任务 + 1 会话）
        seedData()
        let backupURLExported = await service.exportJSONAsync()
        let backupURL = try XCTUnwrap(backupURLExported)
        XCTAssertEqual(try persistence.viewContext.count(for: Task.fetchRequest()), 1)

        // When - 直接恢复（BackupService 内部会先清空现有数据，再导入）
        let restored = service.importJSON(from: backupURL)

        // Then - 数据完整恢复（未重复），且会话-任务关联保留
        XCTAssertTrue(restored, "恢复应成功")
        let tasks = try persistence.viewContext.fetch(Task.fetchRequest())
        let sessions = try persistence.viewContext.fetch(FocusSession.fetchRequest())
        XCTAssertEqual(tasks.count, 1, "恢复后任务应为 1（清空生效，未产生重复）")
        XCTAssertEqual(tasks.first?.title, "备份任务")
        XCTAssertEqual(sessions.count, 1, "恢复后会话应为 1")
        XCTAssertEqual(sessions.first?.task?.id, tasks.first?.id, "会话-任务关联应恢复")
        XCTAssertEqual(sessions.first?.status, SessionStatus.completed.rawValue)
    }

    func testImportJSON_InvalidFile_ThenReturnsFalse() {
        // Given - 非法 JSON
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("bad_backup.json")
        try? "not json".write(to: url, atomically: true, encoding: .utf8)

        // When
        let result = service.importJSON(from: url)

        // Then
        XCTAssertFalse(result, "非法文件应恢复失败")
    }

    // MARK: - 原子性与关系恢复（审查 P0/P1 修复验证）

    func testImportJSON_DuplicateIDs_ThenRejectedAndDataUntouched() throws {
        // Given - 先造 1 条数据，再构造含重复任务 id 的备份文件
        seedData()
        XCTAssertEqual(try persistence.viewContext.count(for: Task.fetchRequest()), 1)

        // 复用同一 id 制造重复（真实场景：手工拼接/损坏文件）
        let dupID = UUID()
        let duplicated = BackupPayload(
            version: 1,
            exportedAt: Date(),
            tasks: [
                TaskDTO(id: dupID, title: "A", notes: nil, status: "active",
                        estimatedPomodoros: 1, completedPomodoros: 0, priority: 2,
                        dueDate: nil, recurrenceRule: nil, recurrenceEndDate: nil,
                        displayOrder: 0, createdAt: Date(), updatedAt: Date(), completedAt: nil,
                        estimatedDuration: 0, startDate: nil, isRecurring: false,
                        parentTaskID: nil, tagIDs: []),
                TaskDTO(id: dupID, title: "B", notes: nil, status: "active",
                        estimatedPomodoros: 1, completedPomodoros: 0, priority: 2,
                        dueDate: nil, recurrenceRule: nil, recurrenceEndDate: nil,
                        displayOrder: 0, createdAt: Date(), updatedAt: Date(), completedAt: nil,
                        estimatedDuration: 0, startDate: nil, isRecurring: false,
                        parentTaskID: nil, tagIDs: [])
            ],
            focusSessions: [], habits: [], habitRecords: [], timeRecords: [], scheduleItems: [], tags: []
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dup_backup.json")
        try encoder.encode(duplicated).write(to: url)

        // When
        let result = service.importJSON(from: url)

        // Then - 拒绝恢复，且已有数据未被清空
        XCTAssertFalse(result, "重复 id 的备份应被拒绝")
        XCTAssertEqual(try persistence.viewContext.count(for: Task.fetchRequest()), 1,
                       "拒绝恢复时不应清空现有数据")
        XCTAssertEqual(try persistence.viewContext.count(for: FocusSession.fetchRequest()), 1)
    }

    func testExportImport_TagAndParentRelation_RoundTrip() async throws {
        // Given - 任务 + 标签 + 子任务 + 带标签的会话
        let context = persistence.viewContext
        let parent = Task(context: context)
        parent.storageId = UUID()
        parent.title = "父任务"
        parent.status = TaskStatus.active.rawValue
        parent.estimatedPomodoros = 1
        parent.displayOrder = 0
        parent.createdAt = Date()
        parent.updatedAt = Date()

        let child = Task(context: context)
        child.storageId = UUID()
        child.title = "子任务"
        child.status = TaskStatus.active.rawValue
        child.estimatedPomodoros = 1
        child.displayOrder = 1
        child.parentTask = parent
        child.createdAt = Date()
        child.updatedAt = Date()

        let tag = Tag(context: context)
        tag.storageId = UUID()
        tag.name = "工作"
        tag.createdAt = Date()
        parent.tags.insert(tag)

        let session = FocusSession(context: context)
        session.storageId = UUID()
        session.startTime = Date()
        session.status = SessionStatus.completed.rawValue
        session.phase = FocusPhase.focus.rawValue
        session.actualDuration = 1500
        session.earnedPoints = 10
        session.tag = tag
        session.task = parent
        session.createdAt = Date()
        session.updatedAt = Date()
        try? context.save()

        // When - 导出 → 恢复
        let backupURLExported = await service.exportJSONAsync()
        let backupURL = try XCTUnwrap(backupURLExported)
        XCTAssertTrue(service.importJSON(from: backupURL))

        // Then - 标签 / 父子任务 / 会话标签关系全部恢复
        let tasks = try context.fetch(Task.fetchRequest())
        let tags = try context.fetch(Tag.fetchRequest())
        let sessions = try context.fetch(FocusSession.fetchRequest())
        XCTAssertEqual(tasks.count, 2, "父+子任务都应恢复")
        XCTAssertEqual(tags.count, 1, "标签应恢复")
        XCTAssertEqual(tags.first?.name, "工作")
        let restoredParent = tasks.first { $0.title == "父任务" }
        let restoredChild = tasks.first { $0.title == "子任务" }
        XCTAssertEqual(restoredChild?.parentTask?.id, restoredParent?.id, "父子任务关系应恢复")
        XCTAssertEqual(restoredParent?.tags.first?.name, "工作", "任务标签关系应恢复")
        XCTAssertEqual(sessions.first?.tag?.id, tags.first?.id, "会话标签关系应恢复")
    }
}

// MARK: - 测试辅助

/// `BackupService.exportJSON(completion:)`（2026-10-15 起为后台 completion 形态，
/// 与 DataExportService 逐字同构）的 async 测试包装，供各测试类以 await 调用。
extension BackupService {
    func exportJSONAsync() async -> URL? {
        await withCheckedContinuation { continuation in
            exportJSON { continuation.resume(returning: $0) }
        }
    }
}

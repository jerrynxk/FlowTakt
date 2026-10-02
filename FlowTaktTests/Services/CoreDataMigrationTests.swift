import XCTest
import CoreData
import CloudKit
@testable import FlowTakt

// MARK: - CoreDataMigrationTests
// CoreData 轻量迁移验证（2026-10-03）
//
// 背景：崩溃修复将 `HabitRecord.habit` 关系由 `optional="NO"` 改为 `optional="YES"`
// （Swift 侧 `Habit` → `Habit?`），属 CoreData **轻量迁移**（轻量级变更）。
// 线上已有用户数据库是按旧模型（必填关系）建的，必须验证：
//   1. 旧库能被新模型自动打开（不报迁移失败）
//   2. 已有记录完整保留（不丢数据）
//   3. 迁移后新插入的记录可正常读写
//   4. 迁移后能表达「关系为 nil」这一新状态（历史遗留孤儿记录）
//
// 测试策略：动态构造一个「旧版模型」的 momd（把 habit 改回 optional="NO"），
// 用它在临时目录建库并插入数据，再用 App 当前模型打开该库，验证迁移行为。
// 这比依赖模拟器上的既有数据更可控、可重复。

final class CoreDataMigrationTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("migration_test_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        tempDir = nil
        super.tearDown()
    }

    // MARK: - 旧版模型构造

    /// 基于 App 当前模型构造一个「旧版」模型：把 `HabitRecord.habit` 改回 `optional="NO"`。
    /// 这模拟线上存量数据库的真实 schema。
    private func makeLegacyModel() throws -> NSManagedObjectModel {
        let legacy = PersistenceController.sharedManagedObjectModel.copy() as! NSManagedObjectModel
        guard let habitRecord = legacy.entitiesByName["HabitRecord"] else {
            XCTFail("模型中应存在 HabitRecord 实体")
            throw NSError(domain: "test", code: 1)
        }
        guard let habit = habitRecord.relationshipsByName["habit"] else {
            XCTFail("HabitRecord 应存在 habit 关系")
            throw NSError(domain: "test", code: 2)
        }
        // 改回旧版的必填关系
        habit.isOptional = false
        return legacy
    }

    /// 用旧版模型在临时路径建库，并插入含完整 habit 关系的历史数据。
    /// @return 写入的数据供后续校验
    private func makeLegacyStore() throws -> (storeURL: URL, habitName: String, recordNote: String, habitID: UUID, recordID: UUID) {
        let storeURL = tempDir.appendingPathComponent("Legacy.sqlite")
        let legacyModel = try makeLegacyModel()

        let legacyContainer = NSPersistentContainer(name: "FlowTakt", managedObjectModel: legacyModel)
        let desc = NSPersistentStoreDescription(url: storeURL)
        desc.type = NSSQLiteStoreType
        // 旧模型下不做迁移（写入的就是旧 schema）
        desc.shouldMigrateStoreAutomatically = false
        desc.shouldInferMappingModelAutomatically = false
        legacyContainer.persistentStoreDescriptions = [desc]

        let sem = DispatchSemaphore(value: 0)
        var loadError: Error?
        legacyContainer.loadPersistentStores { _, error in
            loadError = error
            sem.signal()
        }
        XCTAssertEqual(sem.wait(timeout: .now() + 10), .success, "旧版 store 应在 10 秒内加载")
        XCTAssertNil(loadError, "旧版 store 加载不应失败：\(String(describing: loadError))")

        let ctx = legacyContainer.viewContext
        let habitID = UUID()
        let recordID = UUID()
        let habitName = "迁移测试习惯"
        let recordNote = "迁移测试打卡"

        let habit = Habit(entity: NSEntityDescription.entity(forEntityName: "Habit", in: ctx)!, insertInto: ctx)
        habit.id = habitID
        habit.name = habitName
        habit.iconName = "star"
        habit.colorHex = "#FF9500"
        habit.frequency = "daily"
        habit.descriptionText = "旧版数据"
        habit.createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        habit.updatedAt = Date(timeIntervalSince1970: 1_700_000_000)

        let record = HabitRecord(entity: NSEntityDescription.entity(forEntityName: "HabitRecord", in: ctx)!, insertInto: ctx)
        record.id = recordID
        record.date = Date(timeIntervalSince1970: 1_700_000_000)
        record.count = 3
        record.note = recordNote
        record.createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        record.habit = habit   // 旧模型下为必填，必须赋值

        do {
            try ctx.save()
        } catch {
            XCTFail("写入旧版数据失败：\(error)")
            throw error
        }

        return (storeURL, habitName, recordNote, habitID, recordID)
    }

    // MARK: - 迁移验证

    /// 核心用例：用旧模型建库写入数据 → 用 App 当前模型（habit 可选）打开。
    /// 应自动完成轻量迁移，数据完整保留。
    func testMigration_LegacyRequiredHabitToOptional_SucceedsAndPreservesData() throws {
        // Given：旧版 schema 的数据库 + 历史数据
        let legacy = try makeLegacyStore()
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.storeURL.path),
                      "旧版 sqlite 文件应已创建")

        // When：用 App 当前模型（habit 为可选关系）打开旧库
        let container = NSPersistentCloudKitContainer(name: "FlowTakt",
                                                      managedObjectModel: PersistenceController.sharedManagedObjectModel)
        let desc = NSPersistentStoreDescription(url: legacy.storeURL)
        desc.type = NSSQLiteStoreType
        // App 的迁移配置（与 PersistenceController.init 一致）
        desc.shouldMigrateStoreAutomatically = true
        desc.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [desc]

        let sem = DispatchSemaphore(value: 0)
        var migrateError: Error?
        container.loadPersistentStores { _, error in
            migrateError = error
            sem.signal()
        }
        XCTAssertEqual(sem.wait(timeout: .now() + 15), .success, "迁移应在 15 秒内完成")

        // Then：迁移无错误
        XCTAssertNil(migrateError,
                     "轻量迁移应自动完成，不应报错：\(String(describing: migrateError))")
        XCTAssertEqual(container.persistentStoreCoordinator.persistentStores.count, 1,
                       "迁移后应有 1 个 store")

        let ctx = container.viewContext
        // 通过 fetch 按 id 定位（existingObject 需 objectID，此处按业务 id 查询更直观）
        let habitRequest = Habit.fetchRequest()
        habitRequest.predicate = NSPredicate(format: "id == %@", legacy.habitID as CVarArg)
        let habit = try XCTUnwrap(ctx.fetch(habitRequest).first,
                                  "迁移后习惯应存在")
        XCTAssertEqual(habit.name, legacy.habitName, "习惯数据应完整保留")

        let recordRequest = HabitRecord.fetchRequest()
        recordRequest.predicate = NSPredicate(format: "id == %@", legacy.recordID as CVarArg)
        let record = try XCTUnwrap(ctx.fetch(recordRequest).first,
                                   "迁移后打卡记录应存在")
        XCTAssertEqual(record.count, 3, "打卡次数应完整保留")
        XCTAssertEqual(record.note, legacy.recordNote, "备注应完整保留")

        // 迁移后关系仍应可读（这是崩溃修复前会强解包的地方）
        XCTAssertEqual(record.habit?.id, legacy.habitID, "关系迁移后应仍可访问")
    }

    /// 迁移后能表达「关系为 nil」——这是本次改动的核心目的。
    /// 修复前该状态无法表达（会 EXC_BAD_ACCESS），修复后应可安全读写。
    func testMigration_AfterMigration_CanRepresentNilHabitRelation() throws {
        let legacy = try makeLegacyStore()

        // 打开并迁移
        let container = NSPersistentCloudKitContainer(name: "FlowTakt",
                                                      managedObjectModel: PersistenceController.sharedManagedObjectModel)
        let desc = NSPersistentStoreDescription(url: legacy.storeURL)
        desc.type = NSSQLiteStoreType
        desc.shouldMigrateStoreAutomatically = true
        desc.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [desc]

        let sem = DispatchSemaphore(value: 0)
        container.loadPersistentStores { _, _ in sem.signal() }
        XCTAssertEqual(sem.wait(timeout: .now() + 15), .success)

        let ctx = container.viewContext

        // When：插入一条 habit 为 nil 的记录（模拟 CloudKit 合并产生的孤儿记录）
        let orphan = HabitRecord(entity: NSEntityDescription.entity(forEntityName: "HabitRecord", in: ctx)!, insertInto: ctx)
        orphan.id = UUID()
        orphan.date = Date()
        orphan.count = 1
        orphan.note = "孤儿记录"
        orphan.createdAt = Date()
        orphan.habit = nil   // 修复前此处会因模型必填约束而无法表达

        var saveError: Error?
        do {
            try ctx.save()
        } catch {
            saveError = error
        }
        XCTAssertNil(saveError, "迁移后应能保存 habit 为 nil 的记录：\(String(describing: saveError))")

        // Then：重新读取时关系为 nil 而非崩溃
        ctx.refreshAllObjects()
        let fetched = try ctx.fetch(HabitRecord.fetchRequest())
        let orphanFetched = try XCTUnwrap(fetched.first { $0.note == "孤儿记录" })
        XCTAssertNil(orphanFetched.habit,
                     "孤儿记录的 habit 应为 nil（修复后不再 EXC_BAD_ACCESS）")
    }

    /// 迁移后 HabitService 的完整读写链路正常（服务层不因模型变更而破坏）。
    @MainActor
    func testMigration_ThenHabitServiceWorksEndToEnd() throws {
        let legacy = try makeLegacyStore()

        // 用 PersistenceController 的测试入口打开旧库
        let container = NSPersistentCloudKitContainer(name: "FlowTakt",
                                                      managedObjectModel: PersistenceController.sharedManagedObjectModel)
        let desc = NSPersistentStoreDescription(url: legacy.storeURL)
        desc.type = NSSQLiteStoreType
        desc.shouldMigrateStoreAutomatically = true
        desc.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [desc]
        let sem = DispatchSemaphore(value: 0)
        container.loadPersistentStores { _, _ in sem.signal() }
        XCTAssertEqual(sem.wait(timeout: .now() + 15), .success)

        let persistence = PersistenceController(testingWithContainer: container)
        let service = HabitService(persistenceController: persistence)

        // 迁移后的历史数据可被服务层读取
        let habits = service.fetchAllHabits()
        XCTAssertTrue(habits.contains { $0.name == legacy.habitName },
                      "迁移后 HabitService 应能读到历史习惯")

        // 可继续新增打卡（写入路径正常）
        let habit = try XCTUnwrap(habits.first)
        let newRecord = service.checkIn(habit: habit, count: 1, note: "迁移后新增")
        XCTAssertEqual(newRecord.habit?.id, habit.id, "新增记录应正确关联习惯")

        // 级联删除正常（崩溃修复 P0-3）
        service.deleteHabit(habit)
        let after = service.fetchAllHabits()
        XCTAssertFalse(after.contains { $0.id == habit.id }, "习惯应被删除")
    }

    /// 验证当前模型确实是「habit 可选」，即修复已生效（防止回归到必填）。
    func testCurrentModel_HabitRelation_IsOptional() throws {
        guard let habitRecord = PersistenceController.sharedManagedObjectModel
            .entitiesByName["HabitRecord"],
              let habit = habitRecord.relationshipsByName["habit"] else {
            XCTFail("应存在 HabitRecord.habit 关系")
            return
        }
        XCTAssertTrue(habit.isOptional,
                      "HabitRecord.habit 应为可选关系（崩溃修复 2026-10-02），否则孤儿记录会 EXC_BAD_ACCESS")
    }
}

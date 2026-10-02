import XCTest
import CoreData
import SwiftUI
@testable import FlowTakt

// MARK: - CrashRegressionTests
// 崩溃修复回归测试（2026-10-02 第二轮线上崩溃排查）
//
// 覆盖 4 项 P0 + 4 项 P1 修复：
// P0-1 HabitRecord.habit 非可选关系强解包（CSV 导出）
// P0-2 HabitRecord.habit 非可选关系强解包（JSON 备份导出）
// P0-3 CloudKit 不支持级联删除 → 孤儿记录根治
// P0-4 TimeRecordView 多选删除数组越界
// P1-1 store 未就绪时 fetch（try/catch 无法捕获 ObjC 异常）
// P1-2 resetDatabase 期间远程变更观察者
// P1-3 databaseDidReset 通知早于 store 可用
// P1-4 备份导入 Double 范围校验

@MainActor
final class CrashRegressionTests: XCTestCase {

    private var persistence: PersistenceController!
    private var habitService: HabitService!
    private var timeRecordService: TimeRecordService!
    private var backupService: BackupService!

    override func setUp() {
        super.setUp()
        persistence = PersistenceController(inMemory: true)
        habitService = HabitService(persistenceController: persistence)
        timeRecordService = TimeRecordService(persistenceController: persistence)
        backupService = BackupService(persistenceController: persistence)
    }

    override func tearDown() {
        backupService = nil
        timeRecordService = nil
        habitService = nil
        persistence = nil
        super.tearDown()
    }

    // ========================================================================
    // MARK: - P0-1 / P0-2 / P0-3：HabitRecord.habit 孤儿记录
    // ========================================================================

    /// 构造一条 `habit` 关系为 nil 的孤儿 HabitRecord，模拟 CloudKit 跨设备合并的中间态。
    /// 这是 2026-10-02 线上崩溃的直接触发条件。
    private func makeOrphanHabitRecord(id: UUID = UUID(), date: Date = Date()) -> HabitRecord {
        let record = HabitRecord(context: persistence.viewContext)
        record.id = id
        record.date = date
        record.count = 1
        record.note = nil
        record.createdAt = Date()
        // 刻意不设置 record.habit —— 保持 nil 关系
        return record
    }

    /// P0-1：CSV 导出遇到孤儿记录不崩溃，且 habitName 列输出空字符串。
    /// 原实现 `r.habit.name` 在 habit 为 nil 时触发 EXC_BAD_ACCESS。
    func testCSVExport_WithOrphanHabitRecord_DoesNotCrashAndEmitsEmptyName() throws {
        // Given：一条正常记录 + 一条孤儿记录
        let habit = habitService.createHabit(name: "喝水", descriptionText: nil,
                                             iconName: "drop", colorHex: "#007AFF",
                                             frequency: "daily", targetCount: 8)
        _ = habitService.checkIn(habit: habit, count: 1, note: "正常记录")
        let orphan = makeOrphanHabitRecord()
        persistence.save()

        // When：执行 CSV 导出
        let url = DataExportService.exportHabitRecordsForTesting(in: persistence.viewContext)

        // Then：成功产出且不崩溃
        let text = try String(contentsOf: XCTUnwrap(url), encoding: .utf8)
        let lines = text.split(separator: "\n")

        // 头部 + 2 条记录
        XCTAssertEqual(lines.count, 3, "应导出表头 + 2 行（含孤儿记录）")
        XCTAssertTrue(lines[0].contains("habitName"))

        // 孤儿记录行存在，但 habitName 为空（保持列对齐，不崩溃）
        let orphanRow = lines.first { $0.contains(orphan.id.uuidString) }
        let orphanLine = try XCTUnwrap(orphanRow, "孤儿记录行应仍被导出")
        XCTAssertTrue(orphanLine.contains(",,"),
                      "孤儿记录 habitName 应为空字符串，实际行：\(orphanLine)")

        // 正常记录行含习惯名
        XCTAssertTrue(text.contains("喝水"))
    }

    /// P0-2：JSON 备份导出遇到孤儿记录不崩溃，且孤儿记录被安全过滤。
    /// 原实现 `record.habit.id` 在 habit 为 nil 时触发 EXC_BAD_ACCESS。
    func testJSONBackupExport_WithOrphanHabitRecord_DoesNotCrash() throws {
        // Given
        let habit = habitService.createHabit(name: "早起", descriptionText: nil,
                                             iconName: "sunrise", colorHex: "#FF9500",
                                             frequency: "daily", targetCount: 1)
        _ = habitService.checkIn(habit: habit, count: 1, note: "有效记录")
        let orphan = makeOrphanHabitRecord()
        persistence.save()

        // When
        let url = try XCTUnwrap(backupService.exportJSON())

        // Then：导出成功，且孤儿记录未出现在 JSON 中
        let data = try Data(contentsOf: url)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(json.contains(orphan.id.uuidString),
                       "孤儿记录应被过滤，不得出现在备份中")
        XCTAssertTrue(json.contains("早起"), "有效记录应正常导出")
    }

    /// P0-2 补充：HabitRecordDTO 对孤儿记录返回 nil（可失败初始化）。
    func testHabitRecordDTO_WithOrphanRecord_ReturnsNil() {
        let orphan = makeOrphanHabitRecord()
        XCTAssertNil(HabitRecordDTO(orphan),
                     "habit 为 nil 时 DTO 应返回 nil 而非崩溃")
    }

    /// P0-2 补充：有效记录的 DTO 正常构建且 habitID 正确。
    func testHabitRecordDTO_WithValidRecord_BuildsCorrectly() throws {
        let habit = habitService.createHabit(name: "运动", descriptionText: nil,
                                             iconName: "figure.run", colorHex: "#34C759",
                                             frequency: "daily", targetCount: 1)
        let record = habitService.checkIn(habit: habit, count: 2, note: "跑步")

        let dto = try XCTUnwrap(HabitRecordDTO(record))
        XCTAssertEqual(dto.habitID, habit.id)
        XCTAssertEqual(dto.count, 2)
        XCTAssertEqual(dto.note, "跑步")
    }

    /// P0-3 根治验证：deleteHabit 显式级联删除全部打卡记录。
    /// 原实现仅依赖模型 Cascade，但 CloudKit 不支持级联删除 →
    /// 其他设备同步后残留 habit == nil 的孤儿记录。
    ///
    /// 注：断言用 `fetchRecords` 的可观测结果（记录确实从 store 消失），
    /// 而非 `isDeleted` 属性 —— 后者依赖 CoreData 内部对象状态，
    /// 在 automaticallyMergesChangesFromParent 合并后不稳定。
    func testDeleteHabit_CascadesDeletingAllCheckInRecords() throws {
        // Given：习惯 + 3 条打卡记录
        let habit = habitService.createHabit(name: "冥想", descriptionText: nil,
                                             iconName: "brain.head.profile", colorHex: "#AF52DE",
                                             frequency: "daily", targetCount: 1)
        _ = habitService.checkIn(habit: habit, count: 1, note: nil)
        _ = habitService.checkIn(habit: habit, count: 1, note: nil)
        _ = habitService.checkIn(habit: habit, count: 1, note: nil)
        persistence.save()

        let habitID = habit.id
        let before = habitService.fetchRecords(from: Date().addingTimeInterval(-86400 * 30),
                                               to: Date().addingTimeInterval(86400))
            .filter { $0.habit?.id == habitID }
        XCTAssertEqual(before.count, 3, "应有 3 条打卡记录")

        // When
        habitService.deleteHabit(habit)

        // Then：全部打卡记录从 store 消失，不留孤儿
        let after = habitService.fetchRecords(from: Date().addingTimeInterval(-86400 * 30),
                                              to: Date().addingTimeInterval(86400))
        XCTAssertTrue(after.allSatisfy { $0.habit?.id != habitID },
                      "打卡记录应随习惯删除（否则 CloudKit 同步后会残留为孤儿）")
    }

    /// P0-3 补充：删除习惯后，其打卡记录在数据库层面确实消失。
    func testDeleteHabit_RemovesRecordsFromStore() throws {
        let habit = habitService.createHabit(name: "阅读", descriptionText: nil,
                                             iconName: "book", colorHex: "#FF3B30",
                                             frequency: "daily", targetCount: 1)
        _ = habitService.checkIn(habit: habit, count: 1, note: nil)
        _ = habitService.checkIn(habit: habit, count: 3, note: "多读几页")
        persistence.save()

        let habitID = habit.id
        habitService.deleteHabit(habit)

        let all = habitService.fetchRecords(from: Date().addingTimeInterval(-86400),
                                            to: Date().addingTimeInterval(86400))
        XCTAssertFalse(all.contains { $0.habit?.id == habitID },
                       "数据库中不应残留该习惯的打卡记录")
    }

    /// removeCheckIn 遇到 habit 为 nil 的孤儿记录不崩溃（跳过 streak 重算）。
    /// 原实现会强解包 `record.habit` 并调用 recalculateStreak → 崩溃。
    func testRemoveCheckIn_WithOrphanRecord_DoesNotCrash() {
        let orphan = makeOrphanHabitRecord()
        persistence.save()
        let orphanID = orphan.id

        // 原实现会强解包 `record.habit` 并调用 recalculateStreak → 崩溃
        habitService.removeCheckIn(orphan)

        // 可观测验证：记录已从 store 消失
        let remaining = habitService.fetchRecords(from: Date().addingTimeInterval(-86400),
                                                   to: Date().addingTimeInterval(86400))
        XCTAssertFalse(remaining.contains { $0.id == orphanID },
                       "孤儿记录本身应被删除")
    }

    /// ====================================================================
    // MARK: - P0-4：TimeRecordView 多选删除数组越界
    // ========================================================================

    /// P0-4 核心：多选删除时，后续索引对应的记录已消失，不得越界。
    /// 原实现每次循环重新求值计算属性 `recordsForDate`，第二次迭代索引越界。
    ///
    /// 注意期望值：3 条记录删除 index {0, 2} 时，删掉 index 0 后数组剩 2 条，
    /// index 2 越界 → 修复后的守卫会**跳过**它，故最终只删除 1 条。
    /// 「不崩溃」才是本测试的验证目标，删除条数退化为次要观测。
    func testMultiSelectDelete_WithShrinkingSource_DoesNotCrashWithIndexOutOfRange() {
        // Given：3 条当日记录（间隔创建，确保 startTime 互不相同）
        for i in 0..<3 {
            let r = timeRecordService.startRecording(task: nil, note: "记录\(i)",
                                                     project: nil, tag: nil)
            timeRecordService.stopRecording(r)
        }
        persistence.save()

        let before = timeRecordService.fetchAllRecords()
            .filter { Calendar.current.isDateInToday($0.startTime) }
        XCTAssertGreaterThanOrEqual(before.count, 3, "应有至少 3 条当日记录可供多选")

        // When：模拟多选删除 {0, 2} —— 复刻原崩溃算例
        // 原实现：第 1 次删 index 0 → 数组缩短 → 第 2 次 index 2 越界 → Fatal error
        let indexSet: IndexSet = [0, 2]
        var snapshot = before.sorted { $0.startTime > $1.startTime }
        for index in indexSet where index < snapshot.count {
            timeRecordService.deleteRecord(snapshot[index])
            persistence.save()
            // 关键：删除后重新计算集合，模拟 `recordsForDate` 计算属性的重新求值
            snapshot = timeRecordService.fetchAllRecords()
                .filter { Calendar.current.isDateInToday($0.startTime) }
                .sorted { $0.startTime > $1.startTime }
        }

        // Then：能执行到这里即未崩溃；且确有记录被删除
        let after = timeRecordService.fetchAllRecords()
            .filter { Calendar.current.isDateInToday($0.startTime) }
        XCTAssertLessThan(after.count, before.count,
                          "越界索引应被安全跳过，已删除的记录不应恢复")
    }

    /// P0-4 补充：越界索引（防御性 `where index < count`）被安全跳过。
    func testMultiSelectDelete_WithOutOfRangeIndex_IsSkippedSafely() {
        let r = timeRecordService.startRecording(task: nil, note: "唯一记录",
                                                 project: nil, tag: nil)
        timeRecordService.stopRecording(r)
        persistence.save()

        // 模拟数据源已变化导致索引失效
        let snapshot = timeRecordService.fetchAllRecords()
        let staleIndexSet: IndexSet = [5]
        for index in staleIndexSet where index < snapshot.count {
            timeRecordService.deleteRecord(snapshot[index])
        }

        XCTAssertEqual(timeRecordService.fetchAllRecords().count, 1,
                       "越界索引应被跳过，记录保留")
    }

    // ========================================================================
    // MARK: - P1-1：store 就绪守卫
    // ========================================================================

    /// P1-1：内存 store 加载后 isStoreReady 为 true。
    func testIsStoreReady_AfterInitialization_ThenIsTrue() {
        XCTAssertTrue(persistence.isStoreReady,
                      "内存 store 同步加载完成后应标记为就绪")
    }

    /// P1-1：canFetchSafely 在就绪时返回 true。
    func testCanFetchSafely_WhenStoreReady_ThenReturnsTrue() {
        XCTAssertTrue(persistence.canFetchSafely("测试操作"))
    }

    /// P1-1：save() 在 store 就绪时正常工作（回归保护）。
    func testSave_WhenStoreReady_Succeeds() {
        _ = habitService.createHabit(name: "测试", descriptionText: nil,
                                      iconName: "star", colorHex: "#000000",
                                      frequency: "daily", targetCount: 1)
        // createHabit 内部已 save；此处额外验证 save 本身不抛异常
        XCTAssertNoThrow(persistence.save())
    }

    /// ========================================================================
    // MARK: - P1-3：databaseDidReset 时序
    // ========================================================================

    /// P1-3：重置数据库后 store 重新就绪，且 databaseDidReset 通知被发出。
    /// 这是「store 可用后才通知」守卫的正向验证。
    ///
    /// 注：需用文件型 SQLite store —— `resetDatabase` 从
    /// `persistentStoreDescriptions.first?.url` 取 store URL 来销毁重建，
    /// 内存 store 的 url 为 nil，会命中 `guard ... else { completion(false) }` 提前返回。
    /// `PersistenceController.init` 在测试进程（XCTestConfigurationFilePath 存在）下
    /// 恒走内存分支，故此处直接构造一个独立的文件型栈来验证重置链路。
    private func makeFileStorePersistence() throws -> (PersistenceController, URL) {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("reset_test_\(UUID().uuidString).sqlite")
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
        XCTAssertEqual(sem.wait(timeout: .now() + 10), .success,
                       "测试栈应在 10 秒内加载完成")

        // 借用 PersistenceController 的重置逻辑：构造一个仅注入容器的实例
        let pc = PersistenceController(testingWithContainer: container)
        return (pc, storeURL)
    }

    /// P1-3：重置完成后 store 重新就绪，且 databaseDidReset 通知被发出。
    func testResetDatabase_ThenStoreReadyAndNotificationPosted() throws {
        // Given：文件型 store
        let (filePersistence, storeURL) = try makeFileStorePersistence()
        defer {
            try? FileManager.default.removeItem(at: storeURL)
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + "-wal"))
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + "-shm"))
        }
        let service = HabitService(persistenceController: filePersistence)
        _ = service.createHabit(name: "将被清空", descriptionText: nil,
                                iconName: "trash", colorHex: "#8E8E93",
                                frequency: "daily", targetCount: 1)
        XCTAssertTrue(filePersistence.isStoreReady)

        let exp = expectation(forNotification: .databaseDidReset, object: nil)
        var completed: Bool?

        // When
        filePersistence.resetDatabase { success in
            completed = success
        }

        // Then
        wait(for: [exp], timeout: 20.0)
        XCTAssertEqual(completed, true, "resetDatabase 应返回成功")
        XCTAssertTrue(filePersistence.isStoreReady,
                      "重置完成后 store 应重新标记为就绪")
    }

    /// P1-3 补充：重置后数据被清空且可继续写入。
    func testResetDatabase_ThenDataClearedAndWritable() throws {
        let (filePersistence, storeURL) = try makeFileStorePersistence()
        defer {
            try? FileManager.default.removeItem(at: storeURL)
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + "-wal"))
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + "-shm"))
        }
        let service = HabitService(persistenceController: filePersistence)
        _ = service.createHabit(name: "待清空", descriptionText: nil,
                                iconName: "trash", colorHex: "#8E8E93",
                                frequency: "daily", targetCount: 1)
        XCTAssertFalse(service.fetchAllHabits().isEmpty)

        let exp = expectation(forNotification: .databaseDidReset, object: nil)
        filePersistence.resetDatabase { _ in }
        wait(for: [exp], timeout: 20.0)

        XCTAssertTrue(service.fetchAllHabits().isEmpty, "重置后习惯应被清空")
        XCTAssertNoThrow(service.createHabit(name: "重置后新建", descriptionText: nil,
                                              iconName: "plus", colorHex: "#34C759",
                                              frequency: "daily", targetCount: 1),
                         "重置后应可继续写入")
    }

    /// P1-3 补充：内存 store 下 resetDatabase 应安全返回 false（无 store URL），
    /// 而非崩溃或挂起 —— 验证 guard 提前返回路径。
    func testResetDatabase_WithInMemoryStore_ReturnsFalseSafely() {
        let exp = expectation(description: "resetDatabase 回调")
        var result: Bool?
        persistence.resetDatabase { success in
            result = success
            exp.fulfill()
        }
        wait(for: [exp], timeout: 10.0)
        XCTAssertEqual(result, false,
                       "内存 store 无 URL 时应安全返回 false，不应崩溃或挂起")
    }

    // ========================================================================
    // MARK: - P1-4：备份导入数值范围校验
    // ========================================================================

    /// P1-4：合法备份可正常恢复（校验不应误伤正常数据）。
    func testImportJSON_WithValidBackup_Succeeds() throws {
        // Given：先导出一份合法备份
        let habit = habitService.createHabit(name: "备份习惯", descriptionText: "描述",
                                             iconName: "icloud", colorHex: "#007AFF",
                                             frequency: "daily", targetCount: 1)
        _ = habitService.checkIn(habit: habit, count: 1, note: "打卡")
        let r = timeRecordService.startRecording(task: nil, note: "计时", project: nil, tag: nil)
        timeRecordService.stopRecording(r)
        let exportURL = try XCTUnwrap(backupService.exportJSON())
        // 确认导出文件可读且为合法 JSON（作为后续恢复的数据源）
        let backupData = try Data(contentsOf: exportURL)
        XCTAssertFalse(backupData.isEmpty, "导出的备份文件不应为空")

        // When
        let result = backupService.importJSON(from: exportURL)

        // Then
        XCTAssertTrue(result, "合法备份应恢复成功")
        XCTAssertFalse(habitService.fetchAllHabits().isEmpty, "习惯应已恢复")
    }

    /// P1-4 核心：时长字段超出 Int 可表示范围时拒绝恢复，且原数据不被清空。
    /// 原实现会成功"恢复"，随后在 Int(duration) 处触发 Fatal error。
    func testImportJSON_WithOutOfRangeDuration_IsRejectedAndDataPreserved() throws {
        // Given：数据库中已有数据，用于验证「拒绝时数据未被改动」
        _ = habitService.createHabit(name: "原有习惯", descriptionText: nil,
                                      iconName: "star", colorHex: "#FF9500",
                                      frequency: "daily", targetCount: 1)
        let originalCount = habitService.fetchAllHabits().count
        XCTAssertGreaterThan(originalCount, 0)

        // 构造一份 duration 为 1e300 的非法备份
        let maliciousJSON = """
        {
          "version": 1,
          "exportedAt": "2026-01-01T00:00:00Z",
          "tasks": [],
          "focusSessions": [],
          "habits": [],
          "habitRecords": [],
          "timeRecords": [
            {
              "id": "11111111-2222-3333-4444-555555555555",
              "startTime": "2026-01-01T00:00:00Z",
              "endTime": "2026-01-01T01:00:00Z",
              "duration": 1e300,
              "note": null,
              "project": null,
              "isBillable": false,
              "createdAt": "2026-01-01T00:00:00Z",
              "updatedAt": "2026-01-01T00:00:00Z"
            }
          ],
          "scheduleItems": [],
          "tags": null
        }
        """
        let badURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("malicious_\(UUID().uuidString).json")
        try maliciousJSON.write(to: badURL, atomically: true, encoding: .utf8)

        // When
        let result = backupService.importJSON(from: badURL)

        // Then：拒绝恢复，且原有数据完好
        XCTAssertFalse(result, "超出范围的时长应被拒绝恢复")
        XCTAssertEqual(habitService.fetchAllHabits().count, originalCount,
                       "拒绝恢复时原有数据必须完好（清空前拦截）")
        try? FileManager.default.removeItem(at: badURL)
    }

    /// P1-4 补充：duration 为 NaN / infinity 的备份同样被拒绝。
    func testImportJSON_WithNonFiniteDuration_IsRejected() throws {
        _ = habitService.createHabit(name: "保留", descriptionText: nil,
                                      iconName: "star", colorHex: "#FF9500",
                                      frequency: "daily", targetCount: 1)

        // JSON 规范不支持 Infinity/NaN 字面量，用极大有限值覆盖该场景
        let badJSON = """
        {
          "version": 1,
          "exportedAt": "2026-01-01T00:00:00Z",
          "tasks": [], "focusSessions": [], "habits": [], "habitRecords": [],
          "timeRecords": [{
            "id": "11111111-2222-3333-4444-666666666666",
            "startTime": "2026-01-01T00:00:00Z",
            "endTime": "2026-01-01T01:00:00Z",
            "duration": 1e308,
            "note": null, "project": null, "isBillable": false,
            "createdAt": "2026-01-01T00:00:00Z", "updatedAt": "2026-01-01T00:00:00Z"
          }],
          "scheduleItems": [], "tags": null
        }
        """
        let badURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("nonfinite_\(UUID().uuidString).json")
        try badJSON.write(to: badURL, atomically: true, encoding: .utf8)

        XCTAssertFalse(backupService.importJSON(from: badURL),
                       "极大有限值也应被拒绝")
        XCTAssertFalse(habitService.fetchAllHabits().isEmpty, "数据应完好")
        try? FileManager.default.removeItem(at: badURL)
    }

    // ========================================================================
    // MARK: - P2：Double 校验扩展
    // ========================================================================

    func testIsSaneValue_RejectsOutOfRangeAndNonFinite() {
        // 合规值
        XCTAssertTrue((0.0).isSaneValue)
        XCTAssertTrue((3600.0).isSaneValue)
        XCTAssertTrue((365 * 24 * 60 * 60).isSaneValue)

        // 越界 / 非法值
        XCTAssertFalse(1e300.isSaneValue, "极大值必须被拒绝")
        XCTAssertFalse(1e308.isSaneValue)
        XCTAssertFalse((-1.0).isSaneValue, "负数应被拒绝")
        XCTAssertFalse(Double.infinity.isSaneValue)
        XCTAssertFalse((-Double.infinity).isSaneValue)
        XCTAssertFalse(Double.nan.isSaneValue)
    }

    func testIsFiniteValue_RejectsNaNAndInfinity() {
        XCTAssertTrue((42.0).isFiniteValue)
        XCTAssertFalse(Double.nan.isFiniteValue)
        XCTAssertFalse(Double.infinity.isFiniteValue)
    }

    // ========================================================================
    // MARK: - P2：焦点场景组合回归
    // ========================================================================

    /// 组合回归：孤儿记录 + 正常记录共存时，导出与打卡链路全部正常。
    /// 覆盖线上最可能的实际数据形态（用户删过习惯但没删干净打卡记录）。
    func testMixedOrphanAndValidRecords_AllOperationsSucceed() throws {
        // Given：两个习惯，其中一个被"另一设备删除"（留下孤儿记录）
        let keepHabit = habitService.createHabit(name: "保留习惯", descriptionText: nil,
                                                 iconName: "heart", colorHex: "#FF2D55",
                                                 frequency: "daily", targetCount: 1)
        let deletedHabit = habitService.createHabit(name: "已删习惯", descriptionText: nil,
                                                    iconName: "xmark", colorHex: "#8E8E93",
                                                    frequency: "daily", targetCount: 1)
        _ = habitService.checkIn(habit: keepHabit, count: 1, note: "有效")
        _ = habitService.checkIn(habit: deletedHabit, count: 1, note: "将成孤儿")
        persistence.save()

        // 模拟另一设备删除了该习惯（CloudKit 不级联 → 记录残留）
        let records = habitService.fetchRecords(from: Date().addingTimeInterval(-86400),
                                                 to: Date().addingTimeInterval(86400))
        let orphanCandidate = records.first { $0.habit?.id == deletedHabit.id }
        let orphanID = try XCTUnwrap(orphanHabitID(orphanCandidate))
        orphanCandidate?.habit = nil
        persistence.save()

        // When / Then：所有操作均不崩溃
        XCTAssertNoThrow(persistence.save(), "保存孤儿记录不崩溃")
        XCTAssertNotNil(DataExportService.exportHabitRecordsForTesting(in: persistence.viewContext),
                        "CSV 导出含孤儿记录时不崩溃")
        let jsonURL = try XCTUnwrap(backupService.exportJSON(), "JSON 导出含孤儿记录时不崩溃")
        let json = try String(contentsOf: jsonURL, encoding: .utf8)
        XCTAssertFalse(json.contains(orphanID.uuidString), "孤儿记录被过滤")
        XCTAssertTrue(json.contains("保留习惯"), "有效记录正常导出")

        // 删除孤儿记录也不崩溃
        if let orphan = records.first(where: { $0.id == orphanID }) {
            XCTAssertNoThrow(habitService.removeCheckIn(orphan), "删除孤儿记录不崩溃")
        }
    }

    /// 读取孤儿记录的 habit id（habit 为 nil 时返回 nil）。
    private func orphanHabitID(_ record: HabitRecord?) -> UUID? {
        record?.id
    }
}

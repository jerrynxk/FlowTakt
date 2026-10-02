import XCTest
import CoreData
@testable import FlowTakt

// MARK: - TimeRecordServiceTests
// 测试 TimeRecordService：创建/停止/更新/删除记录、查询、统计

@MainActor
final class TimeRecordServiceTests: XCTestCase {
    var persistence: PersistenceController!
    var service: TimeRecordService!

    override func setUp() {
        super.setUp()
        persistence = PersistenceController(inMemory: true)
        service = TimeRecordService(persistenceController: persistence)
    }

    override func tearDown() {
        service = nil
        persistence = nil
        super.tearDown()
    }

    // ========================================================================
    // MARK: - 开始记录
    // ========================================================================

    func testStartRecording_GivenNoParams_ThenCreatesRecordWithDefaults() {
        let record = service.startRecording(task: nil, note: nil, project: nil, tag: nil)

        XCTAssertNotNil(record.id)
        XCTAssertNotNil(record.startTime)
        XCTAssertEqual(record.duration, 0)
        XCTAssertTrue(record.isBillable)
        XCTAssertNotNil(record.createdAt)
        XCTAssertNotNil(record.updatedAt)
        XCTAssertNil(record.task)
        XCTAssertNil(record.tag)
    }

    func testStartRecording_GivenTaskAndProject_ThenPropertiesAssigned() {
        let context = persistence.viewContext
        let task = Task(context: context)
        task.id = UUID()
        task.title = "编码任务"
        task.status = TaskStatus.active.rawValue
        task.estimatedPomodoros = 3
        task.completedPomodoros = 0
        task.priority = 2
        task.displayOrder = 0
        task.createdAt = Date()
        task.updatedAt = Date()

        let tag = Tag(context: context)
        tag.id = UUID()
        tag.name = "工作"
        tag.colorHex = "#007AFF"
        try? context.save()

        let record = service.startRecording(task: task, note: "前端开发", project: "项目A", tag: tag)

        XCTAssertEqual(record.note, "前端开发")
        XCTAssertEqual(record.project, "项目A")
        XCTAssertEqual(record.task?.id, task.id)
        XCTAssertEqual(record.tag?.id, tag.id)
        XCTAssertTrue(record.isBillable)
    }

    // ========================================================================
    // MARK: - 停止记录
    // ========================================================================

    func testStopRecording_ThenSetsEndTimeAndDuration() {
        let record = service.startRecording(task: nil, note: nil, project: nil, tag: nil)

        // 短暂等待以确保 duration > 0
        Thread.sleep(forTimeInterval: 0.01)

        // When
        service.stopRecording(record)

        // Then
        XCTAssertNotNil(record.endTime)
        XCTAssertGreaterThan(record.duration, 0)
        XCTAssertNotNil(record.updatedAt)
    }

    // ========================================================================
    // MARK: - 更新记录
    // ========================================================================

    func testUpdateRecord_GivenPartialFields_ThenOnlyUpdatesProvided() {
        let record = service.startRecording(task: nil, note: "原始备注", project: "原项目", tag: nil)

        service.updateRecord(record, note: "新备注", project: nil, isBillable: false, tag: nil)

        XCTAssertEqual(record.note, "新备注")
        XCTAssertEqual(record.project, "原项目") // 未更新
        XCTAssertFalse(record.isBillable)
    }

    func testUpdateRecord_GivenTag_ThenTagUpdated() {
        let record = service.startRecording(task: nil, note: nil, project: nil, tag: nil)

        let tag = Tag(context: persistence.viewContext)
        tag.id = UUID()
        tag.name = "标签"
        tag.colorHex = "#34C759"
        try? persistence.viewContext.save()

        service.updateRecord(record, note: nil, project: nil, isBillable: nil, tag: tag)

        XCTAssertEqual(record.tag?.id, tag.id)
    }

    // ========================================================================
    // MARK: - 删除记录
    // ========================================================================

    func testDeleteRecord_ThenRecordIsRemoved() {
        let record = service.startRecording(task: nil, note: nil, project: nil, tag: nil)
        XCTAssertEqual(service.fetchAllRecords().count, 1)

        service.deleteRecord(record)

        XCTAssertEqual(service.fetchAllRecords().count, 0)
    }

    // ========================================================================
    // MARK: - 获取记录
    // ========================================================================

    func testFetchAllRecords_WhenMultiple_ThenSortedByStartTimeDescending() {
        _ = service.startRecording(task: nil, note: "第一条", project: nil, tag: nil)
        Thread.sleep(forTimeInterval: 0.01)
        _ = service.startRecording(task: nil, note: "第二条", project: nil, tag: nil)

        let records = service.fetchAllRecords()

        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records[0].note, "第二条", "最新的记录应在前面")
        XCTAssertEqual(records[1].note, "第一条")
    }

    func testFetchRecords_GivenDateRange_ThenReturnsMatchingRecords() {
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date())!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date())!

        _ = service.startRecording(task: nil, note: nil, project: nil, tag: nil)

        let records = service.fetchRecords(from: yesterday, to: tomorrow)

        XCTAssertEqual(records.count, 1)
    }

    func testFetchRecords_WhenNothingInRange_ThenReturnsEmpty() {
        let farFuture = Date().addingTimeInterval(86400 * 30)
        let records = service.fetchRecords(from: farFuture, to: farFuture.addingTimeInterval(86400))

        XCTAssertTrue(records.isEmpty)
    }

    func testFetchRecordsForTask_ThenReturnsTaskRecords() {
        let context = persistence.viewContext
        let task = Task(context: context)
        task.id = UUID()
        task.title = "任务A"
        task.status = TaskStatus.active.rawValue
        task.estimatedPomodoros = 1
        task.completedPomodoros = 0
        task.priority = 2
        task.displayOrder = 0
        task.createdAt = Date()
        task.updatedAt = Date()
        try? context.save()

        _ = service.startRecording(task: task, note: "记录1", project: nil, tag: nil)
        _ = service.startRecording(task: nil, note: "记录2", project: nil, tag: nil)

        let records = service.fetchRecordsForTask(task)

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.note, "记录1")
    }

    // ========================================================================
    // MARK: - 统计
    // ========================================================================

    func testGetTotalDuration_GivenDateRange_ThenSumsDurations() {
        let record = service.startRecording(task: nil, note: nil, project: nil, tag: nil)
        Thread.sleep(forTimeInterval: 0.05)
        service.stopRecording(record)

        let yesterday = Date().addingTimeInterval(-86400)
        let tomorrow = Date().addingTimeInterval(86400)
        let total = service.getTotalDuration(from: yesterday, to: tomorrow)

        XCTAssertGreaterThan(total, 0)
    }

    func testGetDurationByProject_ThenGroupsByProject() {
        let r1 = service.startRecording(task: nil, note: nil, project: "前端", tag: nil)
        Thread.sleep(forTimeInterval: 0.01)
        service.stopRecording(r1)

        let r2 = service.startRecording(task: nil, note: nil, project: "后端", tag: nil)
        Thread.sleep(forTimeInterval: 0.01)
        service.stopRecording(r2)

        let yesterday = Date().addingTimeInterval(-86400)
        let tomorrow = Date().addingTimeInterval(86400)
        let grouped = service.getDurationByProject(from: yesterday, to: tomorrow)

        XCTAssertEqual(grouped.count, 2)
    }
}

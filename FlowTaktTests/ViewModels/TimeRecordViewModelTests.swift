import XCTest
import CoreData
import Combine
@testable import FlowTakt

// MARK: - TimeRecordViewModelTests
// 测试 TimeRecordViewModel：计时器开始/停止/删除、记录刷新、今日总时长

final class TimeRecordViewModelTests: XCTestCase {
    var persistence: PersistenceController!
    var mockTimeRecordService: MockTimeRecordService!
    var viewModel: TimeRecordViewModel!
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        persistence = PersistenceController(inMemory: true)
        mockTimeRecordService = MockTimeRecordService()
        viewModel = TimeRecordViewModel(
            timeRecordService: mockTimeRecordService,
            persistenceController: persistence
        )
        cancellables = Set<AnyCancellable>()
    }

    override func tearDown() {
        viewModel = nil
        mockTimeRecordService = nil
        persistence = nil
        cancellables = nil
        super.tearDown()
    }

    // ========================================================================
    // MARK: - 初始状态
    // ========================================================================

    func testInitialState_WhenCreated_ThenAllPropertiesAreDefault() {
        XCTAssertTrue(viewModel.records.isEmpty)
        XCTAssertFalse(viewModel.isRecording)
        XCTAssertNil(viewModel.currentRecord)
        XCTAssertEqual(viewModel.totalDurationToday, 0)
    }

    // ========================================================================
    // MARK: - 开始记录
    // ========================================================================

    func testStartRecording_ThenSetsRecordingState() {
        // Given
        let record = TimeRecord(context: persistence.viewContext)
        record.id = UUID()
        record.startTime = Date()
        record.duration = 0
        record.isBillable = true
        record.createdAt = Date()
        record.updatedAt = Date()
        try? persistence.viewContext.save()
        mockTimeRecordService.records = [record]

        // When
        viewModel.startRecording(project: "项目A")

        // Then
        XCTAssertTrue(viewModel.isRecording)
        XCTAssertNotNil(viewModel.currentRecord)
    }

    func testStartRecording_ThenLoadsRecords() {
        let record = TimeRecord(context: persistence.viewContext)
        record.id = UUID()
        record.startTime = Date()
        record.duration = 0
        record.isBillable = true
        record.createdAt = Date()
        record.updatedAt = Date()
        try? persistence.viewContext.save()
        mockTimeRecordService.records = [record]

        // When
        viewModel.startRecording()

        // Then
        XCTAssertEqual(viewModel.records.count, 1)
    }

    func testStartRecording_ThenRefreshesTodayTotal() {
        mockTimeRecordService.totalDurationToReturn = 3600

        let record = TimeRecord(context: persistence.viewContext)
        record.id = UUID()
        record.startTime = Date()
        record.duration = 0
        record.isBillable = true
        record.createdAt = Date()
        record.updatedAt = Date()
        try? persistence.viewContext.save()
        mockTimeRecordService.records = [record]

        // When
        viewModel.startRecording()

        // Then
        XCTAssertEqual(viewModel.totalDurationToday, 3600)
    }

    // ========================================================================
    // MARK: - 防重：正在录制时重复调用忽略
    // ========================================================================

    func testStartRecording_GivenAlreadyRecording_ThenIgnored() {
        // Given
        let record = TimeRecord(context: persistence.viewContext)
        record.id = UUID()
        record.startTime = Date()
        record.duration = 0
        record.isBillable = true
        record.createdAt = Date()
        record.updatedAt = Date()
        try? persistence.viewContext.save()
        mockTimeRecordService.records = [record]
        var startCalls = 0
        mockTimeRecordService.startRecordingCalledHandler = {
            startCalls += 1
        }
        viewModel.startRecording()
        XCTAssertTrue(viewModel.isRecording)

        // When - 已录制时再次调用
        viewModel.startRecording()

        // Then - 不重复创建记录（前一条不会被覆盖而永不停表）
        XCTAssertEqual(startCalls, 1, "正在录制时重复调用 startRecording 应被忽略")
        XCTAssertEqual(viewModel.currentRecord?.id, record.id, "currentRecord 不应被覆盖")
    }

    func testStartRecording_AfterStop_ThenAllowedAgain() {
        // Given
        let record = TimeRecord(context: persistence.viewContext)
        record.id = UUID()
        record.startTime = Date()
        record.duration = 0
        record.isBillable = true
        record.createdAt = Date()
        record.updatedAt = Date()
        try? persistence.viewContext.save()
        mockTimeRecordService.records = [record]
        var startCalls = 0
        mockTimeRecordService.startRecordingCalledHandler = {
            startCalls += 1
        }
        viewModel.startRecording()
        viewModel.stopRecording()
        XCTAssertFalse(viewModel.isRecording)

        // When - 停止后可再次开始
        viewModel.startRecording()

        // Then
        XCTAssertEqual(startCalls, 2, "停止后应允许重新开始记录")
    }

    // ========================================================================
    // MARK: - 停止记录
    // ========================================================================

    func testStopRecording_ThenClearsRecordingState() {
        let record = TimeRecord(context: persistence.viewContext)
        record.id = UUID()
        record.startTime = Date()
        record.duration = 0
        record.isBillable = true
        record.createdAt = Date()
        record.updatedAt = Date()
        try? persistence.viewContext.save()
        mockTimeRecordService.records = [record]
        viewModel.startRecording()

        // When
        viewModel.stopRecording()

        // Then
        XCTAssertFalse(viewModel.isRecording)
        XCTAssertNil(viewModel.currentRecord)
    }

    func testStopRecording_WhenNotRecording_ThenDoesNotCrash() {
        // Given: 不在录制状态
        XCTAssertFalse(viewModel.isRecording)

        // When / Then
        viewModel.stopRecording()
        XCTAssertFalse(viewModel.isRecording, "无当前记录时调用 stopRecording 不应崩溃")
    }

    // ========================================================================
    // MARK: - 删除记录
    // ========================================================================

    func testDeleteRecord_ThenRemovesFromList() {
        let record = TimeRecord(context: persistence.viewContext)
        record.id = UUID()
        record.startTime = Date()
        record.duration = 100
        record.isBillable = true
        record.createdAt = Date()
        record.updatedAt = Date()
        try? persistence.viewContext.save()
        mockTimeRecordService.records = [record]
        viewModel.loadRecords()
        XCTAssertEqual(viewModel.records.count, 1)

        // When
        viewModel.deleteRecord(record)

        // Then
        XCTAssertEqual(viewModel.records.count, 0)
    }

    func testDeleteRecord_WhenIsCurrentRecord_ThenClearsRecordingState() {
        let record = TimeRecord(context: persistence.viewContext)
        record.id = UUID()
        record.startTime = Date()
        record.duration = 0
        record.isBillable = true
        record.createdAt = Date()
        record.updatedAt = Date()
        try? persistence.viewContext.save()
        mockTimeRecordService.records = [record]
        viewModel.startRecording()

        // When: 删除当前正在录制的记录
        viewModel.deleteRecord(record)

        // Then
        XCTAssertFalse(viewModel.isRecording)
        XCTAssertNil(viewModel.currentRecord)
    }

    // ========================================================================
    // MARK: - 今日总时长
    // ========================================================================

    func testRefreshTodayTotal_ThenUpdatesFromService() {
        mockTimeRecordService.totalDurationToReturn = 7200

        // When
        viewModel.refreshTodayTotal()

        // Then
        XCTAssertEqual(viewModel.totalDurationToday, 7200)
    }

    // ========================================================================
    // MARK: - 加载记录
    // ========================================================================

    func testLoadRecords_WhenServiceHasRecords_ThenPopulatesRecords() {
        let record = TimeRecord(context: persistence.viewContext)
        record.id = UUID()
        record.startTime = Date()
        record.duration = 300
        record.isBillable = true
        record.project = "项目X"
        record.createdAt = Date()
        record.updatedAt = Date()
        try? persistence.viewContext.save()
        mockTimeRecordService.records = [record]

        // When
        viewModel.loadRecords()

        // Then
        XCTAssertEqual(viewModel.records.count, 1)
        XCTAssertEqual(viewModel.records.first?.project, "项目X")
    }

    // ========================================================================
    // MARK: - 数据库重置
    // ========================================================================

    func testDatabaseWillReset_ClearsAllState() {
        let record = TimeRecord(context: persistence.viewContext)
        record.id = UUID()
        record.startTime = Date()
        record.duration = 100
        record.isBillable = true
        record.createdAt = Date()
        record.updatedAt = Date()
        try? persistence.viewContext.save()
        mockTimeRecordService.records = [record]
        viewModel.loadRecords()
        mockTimeRecordService.totalDurationToReturn = 500
        viewModel.refreshTodayTotal()
        viewModel.isRecording = true
        viewModel.currentRecord = record

        // When
        NotificationCenter.default.post(name: .databaseWillReset, object: nil)

        // Then
        XCTAssertTrue(viewModel.records.isEmpty)
        XCTAssertFalse(viewModel.isRecording)
        XCTAssertNil(viewModel.currentRecord)
        XCTAssertEqual(viewModel.totalDurationToday, 0)
    }

    // ========================================================================
    // MARK: - Published 属性
    // ========================================================================

    func testPublishedIsRecording_WhenStarted_ThenPublishesTrue() {
        let expectation = expectation(description: "isRecording 发布为 true")

        let record = TimeRecord(context: persistence.viewContext)
        record.id = UUID()
        record.startTime = Date()
        record.duration = 0
        record.isBillable = true
        record.createdAt = Date()
        record.updatedAt = Date()
        try? persistence.viewContext.save()
        mockTimeRecordService.records = [record]

        viewModel.$isRecording
            .dropFirst()
            .sink { value in
                if value == true {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        viewModel.startRecording()

        wait(for: [expectation], timeout: 1.0)
    }
}

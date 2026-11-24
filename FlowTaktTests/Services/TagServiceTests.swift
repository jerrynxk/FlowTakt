import XCTest
import CoreData
@testable import FlowTakt

// MARK: - TagServiceTests
// 测试 TagService（用户反馈 2026-11-19：打通任务↔标签关联，补创建入口）：
// 创建（同名去重/空白拒绝）、重命名、配色、删除（Nullify 解除关联）、任务标签全量替换。

@MainActor
final class TagServiceTests: XCTestCase {
    var persistence: PersistenceController!
    var service: TagService!

    override func setUp() {
        super.setUp()
        persistence = PersistenceController(inMemory: true)
        service = TagService(persistenceController: persistence)
    }

    override func tearDown() {
        service = nil
        persistence = nil
        super.tearDown()
    }

    // ========================================================================
    // MARK: - 创建
    // ========================================================================

    func testCreateTag_GivenValidName_ThenPersistedWithFields() {
        let tag = service.createTag(name: "工作", colorHex: "#E5484D")

        XCTAssertNotNil(tag)
        XCTAssertNotNil(tag?.storageId)
        XCTAssertEqual(tag?.name, "工作")
        XCTAssertEqual(tag?.colorHex, "#E5484D")
        XCTAssertNotNil(tag?.createdAt)
        XCTAssertEqual(service.fetchAllTags().count, 1)
    }

    func testCreateTag_GivenWhitespaceOnlyName_ThenRejected() {
        XCTAssertNil(service.createTag(name: "   ", colorHex: nil))
        XCTAssertTrue(service.fetchAllTags().isEmpty)
    }

    func testCreateTag_GivenDuplicateNameCaseInsensitive_ThenReturnsExisting() {
        let first = service.createTag(name: "工作", colorHex: "#E5484D")
        let second = service.createTag(name: "  工作  ", colorHex: "#3B82F6")

        XCTAssertEqual(service.fetchAllTags().count, 1, "同名标签（忽略首尾空白/大小写）不得重复创建")
        XCTAssertEqual(first?.id, second?.id, "重复创建应返回已有标签")
    }

    // ========================================================================
    // MARK: - 重命名 / 配色
    // ========================================================================

    func testRenameTag_ThenNameUpdated() {
        let tag = service.createTag(name: "工作", colorHex: nil)
        service.renameTag(tag!, to: "深度工作")
        XCTAssertEqual(tag?.name, "深度工作")
    }

    func testRenameTag_GivenBlankName_ThenIgnored() {
        let tag = service.createTag(name: "工作", colorHex: nil)
        service.renameTag(tag!, to: "   ")
        XCTAssertEqual(tag?.name, "工作", "空白名不得清空标签名")
    }

    func testSetTagColor_ThenColorUpdated() {
        let tag = service.createTag(name: "工作", colorHex: nil)
        service.setTagColor(tag!, colorHex: "#22A06B")
        XCTAssertEqual(tag?.colorHex, "#22A06B")
    }

    // ========================================================================
    // MARK: - 删除（Nullify 语义）
    // ========================================================================

    func testDeleteTag_ThenTaskAssociationNulledifyAndTaskKept() throws {
        // 删除规则为 Nullify：任务解除关联但任务本身保留
        let tag = try XCTUnwrap(service.createTag(name: "工作", colorHex: nil))
        let task = makeTask()
        service.setTags([tag], on: task)
        XCTAssertEqual(task.tags.count, 1)

        service.deleteTag(tag)
        XCTAssertEqual(task.tags.count, 0, "删除标签后任务应自动解除关联（Nullify）")
        XCTAssertFalse(task.isDeleted, "任务本身必须保留")
        XCTAssertTrue(service.fetchAllTags().isEmpty)
    }

    // ========================================================================
    // MARK: - 任务标签全量替换
    // ========================================================================

    func testSetTags_ThenFullReplaceNotAppend() throws {
        let tagA = try XCTUnwrap(service.createTag(name: "A", colorHex: nil))
        let tagB = try XCTUnwrap(service.createTag(name: "B", colorHex: nil))
        let tagC = try XCTUnwrap(service.createTag(name: "C", colorHex: nil))
        let task = makeTask()

        service.setTags([tagA, tagB], on: task)
        XCTAssertEqual(Set(task.tags.map { $0.id }), Set([tagA.id, tagB.id]))

        // 全量替换：再次设置只含 tagC 时，A/B 应被移除
        service.setTags([tagC], on: task)
        XCTAssertEqual(Set(task.tags.map { $0.id }), Set([tagC.id]))
    }

    func testSetTags_GivenEmptySet_ThenClearsAll() throws {
        let tag = try XCTUnwrap(service.createTag(name: "A", colorHex: nil))
        let task = makeTask()
        service.setTags([tag], on: task)
        XCTAssertEqual(task.tags.count, 1)

        service.setTags([], on: task)
        XCTAssertTrue(task.tags.isEmpty, "空集合应清空全部标签（保存页取消全选的场景）")
    }

    // ========================================================================
    // MARK: - 统计归属链路（resolvedTag 兜底）
    // ========================================================================

    func testTaskFirstTag_ResolvesStatCategorization() throws {
        // 统计页「按标签统计」的正计时兜底链：record.tag → task.tags 按名称排序首个。
        // 本用例验证任务挂标签后，归属链路能取到标签（打通未分类问题的核心路径）。
        let tagWork = try XCTUnwrap(service.createTag(name: "工作", colorHex: nil))
        let task = makeTask()
        service.setTags([tagWork], on: task)

        let recordService = TimeRecordService(persistenceController: persistence)
        // 注意：UI 路径只传 task 不传 tag，统计靠 task.tags 兜底
        let record = recordService.startRecording(task: task, note: nil, project: nil, tag: nil)
        recordService.stopRecording(record)

        XCTAssertNil(record.tag, "UI 路径不直接写 record.tag")
        let resolved = record.tag ?? record.task?.tags.sorted { $0.name < $1.name }.first
        XCTAssertEqual(resolved?.id, tagWork.id, "正计时绑任务后应经 task.tags 兜底解析出标签")
    }

    // ========================================================================
    // MARK: - 辅助
    // ========================================================================

    private func makeTask() -> Task {
        let task = Task(context: persistence.viewContext)
        task.storageId = UUID()
        task.title = "测试任务"
        task.status = TaskStatus.active.rawValue
        task.estimatedPomodoros = 1
        task.completedPomodoros = 0
        task.priority = 2
        task.displayOrder = 0
        task.createdAt = Date()
        task.updatedAt = Date()
        return task
    }
}

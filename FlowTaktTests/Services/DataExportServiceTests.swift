import XCTest
import CoreData
@testable import FlowTakt

// MARK: - DataExportServiceTests（CSV 导出核心逻辑）

final class DataExportServiceTests: XCTestCase {

    // MARK: csvField 转义（RFC 4180）

    func testCSVField_Nil_ThenEmpty() {
        XCTAssertEqual(DataExportService.csvField(nil), "")
    }

    func testCSVField_PlainString_ThenUnchanged() {
        XCTAssertEqual(DataExportService.csvField("hello"), "hello")
    }

    func testCSVField_Comma_ThenQuoted() {
        XCTAssertEqual(DataExportService.csvField("a,b"), "\"a,b\"")
    }

    func testCSVField_Quote_ThenEscapedDoubleQuote() {
        XCTAssertEqual(DataExportService.csvField("say \"hi\""), "\"say \"\"hi\"\"\"")
    }

    func testCSVField_Newline_ThenQuoted() {
        XCTAssertEqual(DataExportService.csvField("line1\nline2"), "\"line1\nline2\"")
    }

    func testCSVField_Date_ThenISO8601() {
        let date = ISO8601DateFormatter().date(from: "2026-08-11T09:00:00Z")!
        let field = DataExportService.csvField(date)
        XCTAssertEqual(field, "2026-08-11T09:00:00Z")
        XCTAssertFalse(field.contains(","), "ISO8601 日期不含逗号，无需引号")
    }

    func testCSVField_UUID_ThenUUIDString() {
        let uuid = UUID()
        XCTAssertEqual(DataExportService.csvField(uuid), uuid.uuidString)
    }

    // MARK: writeCSV 产出

    func testWriteCSV_ThenFileWithHeaderAndRows() throws {
        let url = try XCTUnwrap(
            DataExportService.writeCSV(
                filename: "unit_test.csv",
                header: ["a", "b"],
                rows: [["1", "2,3"], ["4", "5"]]
            )
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.components(separatedBy: "\n")
        XCTAssertEqual(lines[0], "a,b", "表头")
        // 注意：writeCSV 只负责拼接行；RFC 4180 转义由 csvField 完成（已在上方单独断言）
        XCTAssertEqual(lines[1], "1,2,3")
        XCTAssertEqual(lines[2], "4,5")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
}

import XCTest
@testable import FlowTakt

// MARK: - LunarCalendarTests（农历显示）

final class LunarCalendarTests: XCTestCase {

    private let calendar = Calendar.current

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    func testLunarDateString_NormalDate_ThenReturnsLunarText() {
        // 2026-08-11 的农历应返回「月+日」中文形式
        let lunar = LunarCalendar.lunarDateString(from: date(2026, 8, 11))
        XCTAssertNotNil(lunar, "合法公历日期应返回农历字符串")
        let text = lunar ?? ""
        XCTAssertTrue(text.contains("月"), "农历格式应包含月份名，实际：\(text)")
    }

    func testLunarDateString_NewYear_Then正月() {
        // 2026-02-17 为 2026 农历正月初一（实现：初一返回月份名"正月"）
        let lunar = LunarCalendar.lunarDateString(from: date(2026, 2, 17))
        XCTAssertEqual(lunar, "正月", "春节当天应为 正月，实际：\(lunar ?? "nil")")
    }

    func testLunarDateString_YearBoundary_ThenNonNil() {
        // 年末（公历 2027-02-05 附近为农历年末）不崩溃且返回非 nil
        let lunar = LunarCalendar.lunarDateString(from: date(2027, 2, 5))
        XCTAssertNotNil(lunar)
    }
}

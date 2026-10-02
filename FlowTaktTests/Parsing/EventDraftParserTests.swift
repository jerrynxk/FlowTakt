import XCTest
@testable import FlowTakt

// MARK: - EventDraftParserTests（B2 自然语言快速建日程）

final class EventDraftParserTests: XCTestCase {

    private let calendar = Calendar.current

    /// 固定「now」便于确定性断言
    private func fixedNow(day: Int = 10, month: Int = 8, year: Int = 2026, hour: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func startOf(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    func testParse_明天下午3点开会_ThenTitleAnd15oclock() {
        // Given - 2026-08-10（周一）10:00
        let now = fixedNow()

        // When
        let draft = EventDraftParser.parse("明天下午3点 开会", now: now)

        // Then
        XCTAssertEqual(draft?.title, "开会")
        let expected = calendar.date(from: DateComponents(year: 2026, month: 8, day: 11, hour: 15, minute: 0))!
        XCTAssertEqual(draft?.startDate, expected)
        XCTAssertEqual(draft?.endDate, expected.addingTimeInterval(3600), "默认时长 1 小时")
    }

    func testParse_今天20点看电影_ThenToday20() {
        let now = fixedNow()
        let draft = EventDraftParser.parse("今天 20:00 看电影", now: now)
        XCTAssertEqual(draft?.title, "看电影")
        let expected = calendar.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 20, minute: 0))!
        XCTAssertEqual(draft?.startDate, expected)
    }

    func testParse_下周一上午9点半晨会_ThenNextMonday930() {
        // 2026-08-10 是周一；下周一 = 08-17
        let now = fixedNow()
        let draft = EventDraftParser.parse("下周一上午9点半 晨会", now: now)
        XCTAssertEqual(draft?.title, "晨会")
        let expected = calendar.date(from: DateComponents(year: 2026, month: 8, day: 17, hour: 9, minute: 30))!
        XCTAssertEqual(draft?.startDate, expected)
    }

    func testParse_后天1230午餐_ThenDayAfterTomorrow1230() {
        let now = fixedNow()
        let draft = EventDraftParser.parse("后天 12:30 午餐", now: now)
        XCTAssertEqual(draft?.title, "午餐")
        let expected = calendar.date(from: DateComponents(year: 2026, month: 8, day: 12, hour: 12, minute: 30))!
        XCTAssertEqual(draft?.startDate, expected)
    }

    func testParse_月日无时间_ThenDefault900() {
        let now = fixedNow()
        let draft = EventDraftParser.parse("8月15日 体检", now: now)
        XCTAssertEqual(draft?.title, "体检")
        let expected = calendar.date(from: DateComponents(year: 2026, month: 8, day: 15, hour: 9, minute: 0))!
        XCTAssertEqual(draft?.startDate, expected, "缺时间时默认 9:00")
    }

    func testParse_仅时间词_ThenTodayWithTime() {
        let now = fixedNow()
        let draft = EventDraftParser.parse("下午3点 写方案", now: now)
        XCTAssertEqual(draft?.title, "写方案")
        let expected = calendar.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 15, minute: 0))!
        XCTAssertEqual(draft?.startDate, expected)
    }

    func testParse_空输入_ThenNil() {
        XCTAssertNil(EventDraftParser.parse("  "))
        XCTAssertNil(EventDraftParser.parse(""))
    }

    func testParse_纯时间无标题_ThenNil() {
        let now = fixedNow()
        XCTAssertNil(EventDraftParser.parse("明天下午3点", now: now), "无标题应解析失败，回退完整表单")
    }

    func testParse_本周三_当天就是周三_ThenToday() {
        // 2026-08-12 是周三；无时间词默认 9:00
        let now = fixedNow(day: 12)
        let draft = EventDraftParser.parse("本周三 开会", now: now)
        XCTAssertEqual(draft?.title, "开会")
        let expected = calendar.date(from: DateComponents(year: 2026, month: 8, day: 12, hour: 9, minute: 0))!
        XCTAssertEqual(draft?.startDate, expected, "「本周三」且今天就是周三应指向今天")
    }

    func testParse_本周五_ThenThisFriday() {
        // 2026-08-10 是周一，本周五 = 08-14
        let now = fixedNow(day: 10)
        let draft = EventDraftParser.parse("本周五 团建", now: now)
        XCTAssertEqual(draft?.title, "团建")
        let expected = calendar.date(from: DateComponents(year: 2026, month: 8, day: 14, hour: 9, minute: 0))!
        XCTAssertEqual(draft?.startDate, expected, "「本周五」应指向本周内周五")
    }
}

import XCTest
@testable import Coufunch

final class SpecialAllowancePaydayTests: XCTestCase {
    func testSundayThroughSaturdayWeekPaysFollowingTuesday() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        calendar.firstWeekday = 1
        let sunday = try XCTUnwrap(calendar.date(from:
            DateComponents(year: 2026, month: 10, day: 18)))
        let expected = try XCTUnwrap(calendar.date(from:
            DateComponents(year: 2026, month: 10, day: 27, hour: 10)))
        XCTAssertEqual(SpecialAllowancePayday.followingTuesday(
            weekStart: sunday, calendar: calendar), expected)
    }

    func testFollowingTuesdayAcrossYearBoundary() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        calendar.firstWeekday = 1
        let sunday = try XCTUnwrap(calendar.date(from:
            DateComponents(year: 2026, month: 12, day: 27)))
        let expected = try XCTUnwrap(calendar.date(from:
            DateComponents(year: 2027, month: 1, day: 5, hour: 10)))
        XCTAssertEqual(SpecialAllowancePayday.followingTuesday(
            weekStart: sunday, calendar: calendar), expected)
    }
}

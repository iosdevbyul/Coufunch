import Foundation
import XCTest
@testable import Coufunch

final class CalendarTodayRefreshTests: XCTestCase {
    func testMidnightMovesToFollowingDayInSeoul() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Seoul"))
        let beforeMidnight = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 28, hour: 23, minute: 59, second: 59
        )))
        let midnight = try XCTUnwrap(CalendarTodayRefresh.nextBoundary(
            after: beforeMidnight, calendar: calendar
        ))
        XCTAssertEqual(calendar.dateComponents([.year, .month, .day, .hour, .minute],
                                               from: midnight),
                       DateComponents(year: 2026, month: 10, day: 29, hour: 0, minute: 0))
        let next = try XCTUnwrap(CalendarTodayRefresh.nextBoundary(after: midnight, calendar: calendar))
        XCTAssertEqual(calendar.component(.day, from: next), 30)
    }

    func testMonthEndRollover() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Seoul"))
        let octoberEnd = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 31, hour: 23, minute: 59
        )))
        let next = try XCTUnwrap(CalendarTodayRefresh.nextBoundary(after: octoberEnd, calendar: calendar))
        XCTAssertEqual(calendar.component(.month, from: next), 11)
        XCTAssertEqual(calendar.component(.day, from: next), 1)
    }
}

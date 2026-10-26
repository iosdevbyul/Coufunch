import XCTest
@testable import Coufunch

final class PaydayReminderDateTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return value
    }
    private func date(_ day: Int, _ hour: Int = 19) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    func testWeekdayShiftSchedulesFollowingBusinessDayAtTwoPM() {
        let result = PaydayReminderDate.nextBusinessDay(after: date(19),
            holidays: [], loadedYears: [2026])
        XCTAssertEqual(result, date(20, 14))
    }

    func testFridayShiftRollsForwardToMonday() {
        let result = PaydayReminderDate.nextBusinessDay(after: date(16),
            holidays: [], loadedYears: [2026])
        XCTAssertEqual(result, date(19, 14))
    }

    func testHolidayOnMondayRollsForwardToTuesday() {
        let result = PaydayReminderDate.nextBusinessDay(after: date(16),
            holidays: ["2026-10-19"], loadedYears: [2026])
        XCTAssertEqual(result, date(20, 14))
    }

    func testMissingHolidayYearDoesNotSchedulePotentiallyWrongPayday() {
        XCTAssertNil(PaydayReminderDate.nextBusinessDay(after: date(19),
            holidays: [], loadedYears: []))
    }
}

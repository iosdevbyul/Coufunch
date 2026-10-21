import XCTest
@testable import Coufunch

@MainActor
final class HolidayShiftAttributionTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return value
    }

    private func date(_ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    func testEntireOvernightShiftIsHolidayWhenStartingDateIsHoliday() throws {
        let shift = WorkSession(workplaceID: UUID(), startAt: date(18, 19),
                                endAt: date(19, 4), hourlyRateSnapshot: 10_320)
        let rest = WorkBreak(sessionID: shift.id,
                             startAt: date(18, 23), endAt: date(19, 0))
        let minutes = HolidayWorkMinutes.calculate(session: shift, breaks: [rest],
                                                     holidayDates: ["2026-10-18"])
        XCTAssertEqual(minutes, 480)
        let result = try WorkPayCalculator.calculate(session: shift,
            breaks: [rest], calendar: calendar, holidayPaidMinutes: minutes)
        XCTAssertEqual(result.holidayPremium, 41_280)
        XCTAssertEqual(result.nightMinutes, 300)
    }

    func testOvernightShiftStartingOnRegularDayDoesNotBecomeHolidayAfterMidnight() {
        let shift = WorkSession(workplaceID: UUID(), startAt: date(17, 19),
                                endAt: date(18, 4), hourlyRateSnapshot: 10_320)
        XCTAssertEqual(HolidayWorkMinutes.calculate(session: shift, breaks: [],
            holidayDates: ["2026-10-18"]), 0)
    }

    func testOverlappingUnpaidBreaksAreOnlyRemovedOnceForFullHolidayShift() {
        let shift = WorkSession(workplaceID: UUID(), startAt: date(18, 19),
                                endAt: date(19, 4), hourlyRateSnapshot: 10_320)
        let rests = [
            WorkBreak(sessionID: shift.id, startAt: date(18, 23), endAt: date(19, 1)),
            WorkBreak(sessionID: shift.id, startAt: date(19, 0), endAt: date(19, 2))
        ]
        XCTAssertEqual(HolidayWorkMinutes.calculate(session: shift, breaks: rests,
            holidayDates: ["2026-10-18"]), 360)
    }
}

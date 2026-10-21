import XCTest
@testable import Coufunch

@MainActor
final class HolidayPremiumTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return cal
    }
    private func day(_ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }
    func testEightHolidayHoursAddFiftyPercent() throws {
        let shift = WorkSession(workplaceID: UUID(), startAt: day(9, 9),
                                endAt: day(9, 18), hourlyRateSnapshot: 10_320)
        let rest = WorkBreak(sessionID: shift.id, startAt: day(9, 12), endAt: day(9, 13))
        let pay = try WorkPayCalculator.calculate(session: shift, breaks: [rest],
            calendar: calendar, holidayPaidMinutes: 480)
        XCTAssertEqual(pay.basePay, 82_560)
        XCTAssertEqual(pay.holidayPremium, 41_280)
        XCTAssertEqual(pay.total, 123_840)
        XCTAssertEqual(pay.overtimePremium, 0)
    }
    func testTenHolidayHoursAddHundredPercentBeyondEightWithoutOvertimeDoubleCount() throws {
        let shift = WorkSession(workplaceID: UUID(), startAt: day(9, 8),
                                endAt: day(9, 18), hourlyRateSnapshot: 10_320)
        let pay = try WorkPayCalculator.calculate(session: shift, breaks: [],
            calendar: calendar, holidayPaidMinutes: 600)
        XCTAssertEqual(pay.holidayPremium, 61_920)
        XCTAssertEqual(pay.overtimePremium, 0)
        XCTAssertEqual(pay.total, 165_120)
    }
    func testNonHolidayRemainsUnchanged() throws {
        let shift = WorkSession(workplaceID: UUID(), startAt: day(8, 8),
                                endAt: day(8, 18), hourlyRateSnapshot: 10_320)
        let pay = try WorkPayCalculator.calculate(session: shift, breaks: [],
                                                  calendar: calendar)
        XCTAssertEqual(pay.holidayPremium, 0)
        XCTAssertEqual(pay.total, 113_520)
    }
}

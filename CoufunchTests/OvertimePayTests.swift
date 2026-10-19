import XCTest
@testable import Coufunch

@MainActor
final class OvertimePayTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return value
    }
    private func date(_ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    func testTwoOvertimeHoursWithoutNighttime() throws {
        let shift = WorkSession(workplaceID: UUID(), startAt: date(19, 8),
                                endAt: date(19, 19), status: .completed, hourlyRateSnapshot: 10_320)
        let rest = WorkBreak(sessionID: shift.id, startAt: date(19, 12), endAt: date(19, 13))
        let result = try WorkPayCalculator.calculate(session: shift, breaks: [rest], calendar: calendar)
        XCTAssertEqual(result.workedMinutes, 600)
        XCTAssertEqual(result.overtimeMinutes, 120)
        XCTAssertEqual(result.basePay, 103_200)
        XCTAssertEqual(result.overtimePremium, 10_320)
        XCTAssertEqual(result.total, 113_520)
    }

    func testNightAndOvertimePremiumBothApply() throws {
        let shift = WorkSession(workplaceID: UUID(), startAt: date(19, 19),
                                endAt: date(20, 6), status: .completed, hourlyRateSnapshot: 10_320)
        let rest = WorkBreak(sessionID: shift.id, startAt: date(19, 22), endAt: date(19, 23))
        let result = try WorkPayCalculator.calculate(session: shift, breaks: [rest], calendar: calendar)
        XCTAssertEqual(result.workedMinutes, 600)
        XCTAssertEqual(result.nightMinutes, 420)
        XCTAssertEqual(result.overtimeMinutes, 120)
        XCTAssertEqual(result.nightPremium, 36_120)
        XCTAssertEqual(result.overtimePremium, 10_320)
        XCTAssertEqual(result.total, 149_640)
    }

    func testFixedPayIsNotAutomaticallyIncreased() throws {
        let shift = WorkSession(workplaceID: UUID(), startAt: date(19, 19),
                                endAt: date(20, 6), payMode: .fixedDaily,
                                fixedDailyPaySnapshot: 300_000)
        let result = try WorkPayCalculator.calculate(session: shift, breaks: [], calendar: calendar)
        XCTAssertEqual(result.total, 300_000)
        XCTAssertEqual(result.overtimePremium, 0)
    }

    func testPremiumMayBeDisabledForNonEligibleEmployment() throws {
        let shift = WorkSession(workplaceID: UUID(), startAt: date(19, 8),
                                endAt: date(19, 18), hourlyRateSnapshot: 10_320)
        let result = try WorkPayCalculator.calculate(
            session: shift, breaks: [], calendar: calendar, overtimePremiumEnabled: false)
        XCTAssertEqual(result.overtimePremium, 0)
    }
}

import XCTest
@testable import Coufunch

@MainActor
final class WorkCalculatorTests: XCTestCase {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(identifier: "Asia/Seoul")!
        result.firstWeekday = 1
        return result
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0, month: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    func testOvernightMinimumWageAndNightBreak() throws {
        let workplaceID = UUID()
        let session = WorkSession(workplaceID: workplaceID,
                                  startAt: date(19, 19), endAt: date(20, 4),
                                  status: .completed, hourlyRateSnapshot: 10_320)
        let rest = WorkBreak(sessionID: session.id, startAt: date(19, 22), endAt: date(19, 23))
        let result = try WorkPayCalculator.calculate(session: session, breaks: [rest], calendar: calendar)
        XCTAssertEqual(result.workedMinutes, 480)
        XCTAssertEqual(result.nightMinutes, 300)
        XCTAssertEqual(result.basePay, 82_560)
        XCTAssertEqual(result.nightPremium, 25_800)
        XCTAssertEqual(result.total, 108_360)
    }

    func testOverlappingBreaksCountOnlyOnce() throws {
        let session = WorkSession(workplaceID: UUID(), startAt: date(19, 19),
                                  endAt: date(20, 4), hourlyRateSnapshot: 10_320)
        let breaks = [
            WorkBreak(sessionID: session.id, startAt: date(19, 22), endAt: date(19, 23)),
            WorkBreak(sessionID: session.id, startAt: date(19, 22, 30), endAt: date(19, 23, 30))
        ]
        let result = try WorkPayCalculator.calculate(session: session, breaks: breaks, calendar: calendar)
        XCTAssertEqual(result.workedMinutes, 450)
        XCTAssertEqual(result.nightMinutes, 270)
    }

    func testFixedDailyPayDoesNotAddNightPremium() throws {
        let session = WorkSession(workplaceID: UUID(), startAt: date(19, 19),
                                  endAt: date(20, 4), payMode: .fixedDaily,
                                  fixedDailyPaySnapshot: 300_000)
        let result = try WorkPayCalculator.calculate(session: session, breaks: [], calendar: calendar)
        XCTAssertEqual(result.total, 300_000)
        XCTAssertEqual(result.nightPremium, 0)
    }

    func testMissingHistoricalRateIsRejected() {
        let session = WorkSession(workplaceID: UUID(), startAt: date(19, 9),
                                  endAt: date(19, 18))
        XCTAssertThrowsError(try WorkPayCalculator.calculate(
            session: session, breaks: [], calendar: calendar
        ))
    }

    func testWeeklyAndMonthlyAwardsAreStackedAtAttendanceThresholds() {
        let workplace = Workplace(name: "My workplace", weekStartWeekday: 1)
        let sessions = (18...23).map {
            WorkSession(workplaceID: workplace.id, startAt: date($0, 9), status: .completed)
        }
        let rules = [
            IncentiveRule(workplaceID: workplace.id, name: "Five days", period: .weekly,
                          requiredAttendanceDays: 5, amount: 80_000),
            IncentiveRule(workplaceID: workplace.id, name: "Six days", period: .weekly,
                          requiredAttendanceDays: 6, amount: 40_000),
            IncentiveRule(workplaceID: workplace.id, name: "Month", period: .monthly,
                          requiredAttendanceDays: 15, amount: 70_000)
        ]
        let awards = WorkIncentiveCalculator.awards(
            sessions: sessions, rules: rules, workplace: workplace, calendar: calendar
        )
        XCTAssertEqual(awards.count, 2)
        XCTAssertEqual(awards.reduce(Decimal.zero) { $0 + $1.amount }, 120_000)
    }

    func testExtraSessionOnSameDateDoesNotIncreaseAttendance() {
        let workplace = Workplace(name: "My workplace")
        let sessions = [
            WorkSession(workplaceID: workplace.id, startAt: date(19, 9), status: .completed),
            WorkSession(workplaceID: workplace.id, startAt: date(19, 19), status: .completed)
        ]
        let rule = IncentiveRule(workplaceID: workplace.id, name: "Two days",
                                 period: .weekly, requiredAttendanceDays: 2, amount: 10_000)
        XCTAssertTrue(WorkIncentiveCalculator.awards(
            sessions: sessions, rules: [rule], workplace: workplace, calendar: calendar
        ).isEmpty)
    }

    func testManualIncentivesAreFilteredByWorkplace() {
        let id = UUID()
        let incentives = [
            ManualIncentive(workplaceID: id, earnedOn: date(19, 9), name: "Bonus", amount: 50_000),
            ManualIncentive(workplaceID: UUID(), earnedOn: date(19, 9), name: "Other", amount: 20_000)
        ]
        XCTAssertEqual(WorkIncentiveCalculator.manualTotal(incentives, workplaceID: id), 50_000)
    }
}

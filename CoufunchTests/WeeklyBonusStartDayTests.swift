import XCTest
@testable import Coufunch

final class WeeklyBonusStartDayTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }

    private func date(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: 12))!
    }

    private func completedSession(_ day: Int, workplaceID: UUID) -> WorkSession {
        WorkSession(workplaceID: workplaceID, startAt: date(day), status: .completed)
    }

    func testNewWorkplaceDefaultsToSunday() {
        XCTAssertEqual(Workplace(name: "Coupang").weekStartWeekday, 1)
    }

    func testWeeklyFiveDayBonusRespectsSundayStart() {
        let workplace = Workplace(name: "Warehouse")
        let rule = IncentiveRule(workplaceID: workplace.id, name: "5-day weekly bonus",
                                 period: .weekly, requiredAttendanceDays: 5,
                                 amount: 80_000)
        // Sun 11 through Thu 15 form a five-day bonus week.
        let sessions = (11...15).map { completedSession($0, workplaceID: workplace.id) }
        let sundayAwards = WorkIncentiveCalculator.awards(
            sessions: sessions, rules: [rule], workplace: workplace, calendar: calendar
        )
        XCTAssertEqual(sundayAwards.count, 1)
        XCTAssertEqual(sundayAwards.first?.amount, 80_000)
    }

    func testChangingStartDayMovesWeekBoundary() {
        let workplace = Workplace(name: "Warehouse", weekStartWeekday: 1)
        let rule = IncentiveRule(workplaceID: workplace.id, name: "5-day weekly bonus",
                                 period: .weekly, requiredAttendanceDays: 5,
                                 amount: 80_000)
        // Thu 8 to Mon 12 crosses Sunday boundary but stays inside a Thursday-start week.
        let sessions = (8...12).map { completedSession($0, workplaceID: workplace.id) }
        XCTAssertTrue(WorkIncentiveCalculator.awards(
            sessions: sessions, rules: [rule], workplace: workplace, calendar: calendar
        ).isEmpty)
        workplace.weekStartWeekday = 5 // Thursday in Calendar's weekday indexing.
        XCTAssertEqual(WorkIncentiveCalculator.awards(
            sessions: sessions, rules: [rule], workplace: workplace, calendar: calendar
        ).count, 1)
    }

    func testSixDayAdditionalBonusStacksWithFiveDayBonus() {
        let workplace = Workplace(name: "Warehouse")
        let rules = [
            IncentiveRule(workplaceID: workplace.id, name: "5-day",
                          period: .weekly, requiredAttendanceDays: 5, amount: 80_000),
            IncentiveRule(workplaceID: workplace.id, name: "6-day",
                          period: .weekly, requiredAttendanceDays: 6, amount: 40_000)
        ]
        let sessions = (11...16).map { completedSession($0, workplaceID: workplace.id) }
        let awards = WorkIncentiveCalculator.awards(
            sessions: sessions, rules: rules, workplace: workplace, calendar: calendar
        )
        XCTAssertEqual(awards.count, 2)
        XCTAssertEqual(awards.reduce(Decimal.zero) { $0 + $1.amount }, 120_000)
    }
}

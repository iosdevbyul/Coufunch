import XCTest
@testable import Coufunch

@MainActor
final class WorkdayIncentiveSimulatorTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        calendar.firstWeekday = 1
        return calendar
    }

    private func day(_ number: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: number, hour: 12))!
    }

    func testFifthDayUnlocksWeeklyBonusWithoutSavingHypothetical() {
        let workplace = Workplace(name: "Example", weekStartWeekday: 1)
        let sessions = (18...21).map {
            WorkSession(workplaceID: workplace.id, startAt: day($0), status: .completed)
        }
        let rules = [
            IncentiveRule(workplaceID: workplace.id, name: "Five days", period: .weekly,
                          requiredAttendanceDays: 5, amount: 80_000)
        ]
        let result = WorkdayIncentiveSimulator.simulate(
            candidateDate: day(22), workplace: workplace,
            sessions: sessions, rules: rules, calendar: calendar
        )
        XCTAssertFalse(result.alreadyCompletedOnDate)
        XCTAssertEqual(result.newlyUnlockedBonus, 80_000)
        XCTAssertEqual(result.triggeredRules, ["Five days"])
        XCTAssertEqual(sessions.count, 4)
    }

    func testDuplicateDateAddsNoAttendanceOrBonus() {
        let workplace = Workplace(name: "Example")
        let sessions = [
            WorkSession(workplaceID: workplace.id, startAt: day(20), status: .completed)
        ]
        let rule = IncentiveRule(workplaceID: workplace.id, name: "Two days",
                                 period: .weekly, requiredAttendanceDays: 2, amount: 40_000)
        let result = WorkdayIncentiveSimulator.simulate(
            candidateDate: day(20), workplace: workplace,
            sessions: sessions, rules: [rule], calendar: calendar
        )
        XCTAssertTrue(result.alreadyCompletedOnDate)
        XCTAssertEqual(result.newlyUnlockedBonus, 0)
    }

    func testSixthDayAddsOnlyIncrementalStackableBonus() {
        let workplace = Workplace(name: "Example")
        let sessions = (18...22).map {
            WorkSession(workplaceID: workplace.id, startAt: day($0), status: .completed)
        }
        let rules = [
            IncentiveRule(workplaceID: workplace.id, name: "Five", period: .weekly,
                          requiredAttendanceDays: 5, amount: 80_000),
            IncentiveRule(workplaceID: workplace.id, name: "Six", period: .weekly,
                          requiredAttendanceDays: 6, amount: 40_000)
        ]
        let result = WorkdayIncentiveSimulator.simulate(
            candidateDate: day(23), workplace: workplace,
            sessions: sessions, rules: rules, calendar: calendar
        )
        XCTAssertEqual(result.newlyUnlockedBonus, 40_000)
        XCTAssertEqual(result.simulatedBonus, 120_000)
    }

    func testConfirmedAttendanceDoesNotCountAsAlreadyCompleted() {
        let workplace = Workplace(name: "Example")
        let record = WorkSession(workplaceID: workplace.id,
                                 startAt: day(20), status: .confirmed)
        let rule = IncentiveRule(workplaceID: workplace.id, name: "One",
                                 period: .weekly, requiredAttendanceDays: 1, amount: 10_000)
        let result = WorkdayIncentiveSimulator.simulate(
            candidateDate: day(20), workplace: workplace,
            sessions: [record], rules: [rule], calendar: calendar
        )
        XCTAssertFalse(result.alreadyCompletedOnDate)
        XCTAssertEqual(result.newlyUnlockedBonus, 10_000)
    }
}

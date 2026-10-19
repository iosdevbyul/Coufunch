import XCTest
@testable import Coufunch

@MainActor
final class WorkFinanceSummaryTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Seoul")!
        value.firstWeekday = 1
        return value
    }

    private func date(_ month: Int, _ day: Int, _ hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    func testMonthlySummaryIncludesCompletedSessionsAndManualBonus() {
        let workplace = Workplace(name: "Workplace")
        let complete = WorkSession(workplaceID: workplace.id, startAt: date(10, 19),
            endAt: date(10, 19, 17), status: .completed, payMode: .fixedDaily,
            fixedDailyPaySnapshot: 300_000)
        let pending = WorkSession(workplaceID: workplace.id, startAt: date(10, 20),
            endAt: date(10, 20, 17), status: .applied, payMode: .fixedDaily,
            fixedDailyPaySnapshot: 300_000)
        let manual = ManualIncentive(workplaceID: workplace.id, earnedOn: date(10, 19),
                                     name: "Extra", amount: 40_000)
        let summary = WorkFinanceSummary.summarize(month: date(10, 1),
            sessions: [complete, pending], breaks: [], workplaces: [workplace],
            settings: [], rules: [], manual: [manual], calendar: calendar)
        XCTAssertEqual(summary.completedDays, 1)
        XCTAssertEqual(summary.basePay, 300_000)
        XCTAssertEqual(summary.manualIncentives, 40_000)
        XCTAssertEqual(summary.total, 340_000)
    }

    func testStrategyCountsSameDayOnlyOnce() {
        let workplace = Workplace(name: "Workplace")
        let records = [
            WorkSession(workplaceID: workplace.id, startAt: date(10, 19), status: .completed),
            WorkSession(workplaceID: workplace.id, startAt: date(10, 19, 19), status: .completed)
        ]
        let rule = IncentiveRule(workplaceID: workplace.id, name: "5 days",
                                 period: .weekly, requiredAttendanceDays: 5, amount: 80_000)
        let result = WorkFinanceSummary.opportunities(on: date(10, 20),
            sessions: records, workplaces: [workplace], rules: [rule], calendar: calendar)
        XCTAssertEqual(result.first?.remainingDays, 4)
    }

    func testIncompleteWageRecordsAreFlagged() {
        let workplace = Workplace(name: "Workplace")
        let record = WorkSession(workplaceID: workplace.id, startAt: date(10, 19),
                                 status: .completed, payMode: .minimumHourly)
        let result = WorkFinanceSummary.summarize(month: date(10, 1),
            sessions: [record], breaks: [], workplaces: [workplace],
            settings: [], rules: [], manual: [], calendar: calendar)
        XCTAssertEqual(result.skippedSessions, 1)
    }
}

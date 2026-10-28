import XCTest
@testable import Coufunch

final class WeeklyAllowanceTimelineTests: XCTestCase {
    func testNoWeeklyAwardsProducesEmptyTimeline() {
        XCTAssertTrue(WeeklyAllowanceTimeline.entries(
            sessions: [], workplaces: [], rules: [], receipts: [],
            holidays: [], loadedYears: [], calendar: .current
        ).isEmpty)
    }

    func testUnconfiguredPaymentPolicyDoesNotInventPayday() {
        // An expected payday must not be derived from the daily shift payday.
        // With no eligible award, there is no timeline entry or inferred payday.
        let entries = WeeklyAllowanceTimeline.entries(
            sessions: [], workplaces: [], rules: [], receipts: [],
            holidays: [], loadedYears: [2026], calendar: .current
        )
        XCTAssertFalse(entries.contains { $0.expectedPaymentAt != nil })
    }
    func testSpecialAndRegularWeeklyAwardsHaveDistinctTypes() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        calendar.firstWeekday = 1
        let workplace = Workplace(name: "SEL1")
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 9))!
        let sessions = (0..<6).map { offset in
            WorkSession(workplaceID: workplace.id,
                        startAt: calendar.date(byAdding: .day, value: offset, to: start)!,
                        status: .completed)
        }
        let rules = [
            IncentiveRule(workplaceID: workplace.id, name: "Weekly",
                          period: .weekly, requiredAttendanceDays: 5, amount: 80_000),
            IncentiveRule(workplaceID: workplace.id, name: "Special",
                          period: .weekly, requiredAttendanceDays: 6, amount: 40_000)
        ]
        let result = WeeklyAllowanceTimeline.entries(
            sessions: sessions, workplaces: [workplace], rules: rules,
            receipts: [], holidays: [], loadedYears: [2026], calendar: calendar
        )
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.filter { $0.isSpecialAllowance }.count, 1)
        XCTAssertEqual(result.filter { !$0.isSpecialAllowance }.count, 1)
        XCTAssertNotNil(result.first(where: { $0.isSpecialAllowance })?.expectedPaymentAt)
        XCTAssertNil(result.first(where: { !$0.isSpecialAllowance })?.expectedPaymentAt)
    }

}

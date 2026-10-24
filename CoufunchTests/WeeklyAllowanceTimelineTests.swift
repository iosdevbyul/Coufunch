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
}

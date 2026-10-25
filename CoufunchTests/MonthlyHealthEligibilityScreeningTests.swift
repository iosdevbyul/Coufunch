import XCTest
@testable import Coufunch

final class MonthlyHealthEligibilityScreeningTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return value
    }

    private func session(_ day: Int, workplaceID: UUID, status: WorkSessionStatus = .completed) -> WorkSession {
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: 9))!
        return WorkSession(workplaceID: workplaceID, startAt: start,
                           endAt: start.addingTimeInterval(8 * 3600),
                           status: status)
    }

    func testEightUniqueCompletedDaysQualifyWhenContinuityConfirmed() {
        let workplaceID = UUID()
        let month = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1))!
        let sessions = (1...8).map { session($0, workplaceID: workplaceID) }
            + [session(8, workplaceID: workplaceID), session(9, workplaceID: workplaceID, status: .confirmed)]
        let result = MonthlyHealthEligibilityScreening.evaluate(
            month: month, workplaceID: workplaceID, sessions: sessions,
            employedPreviousMonth: true, startedOnFirstDay: nil, calendar: calendar)
        XCTAssertEqual(result.attendanceDays, 8)
        XCTAssertEqual(result.screening, .enrolled)
    }

    func testUnknownEmploymentHistoryDoesNotAssumeEnrollment() {
        let workplaceID = UUID()
        let month = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1))!
        let sessions = (1...8).map { session($0, workplaceID: workplaceID) }
        let result = MonthlyHealthEligibilityScreening.evaluate(
            month: month, workplaceID: workplaceID, sessions: sessions,
            employedPreviousMonth: nil, startedOnFirstDay: false, calendar: calendar)
        XCTAssertEqual(result.screening, .unknown)
    }

    func testOtherWorkplaceDaysDoNotCount() {
        let workplaceID = UUID()
        let otherID = UUID()
        let month = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1))!
        let sessions = (1...7).map { session($0, workplaceID: workplaceID) }
            + [session(8, workplaceID: otherID)]
        let result = MonthlyHealthEligibilityScreening.evaluate(
            month: month, workplaceID: workplaceID, sessions: sessions,
            employedPreviousMonth: true, startedOnFirstDay: false, calendar: calendar)
        XCTAssertEqual(result.attendanceDays, 7)
        XCTAssertEqual(result.screening, .notEnrolled)
    }
}

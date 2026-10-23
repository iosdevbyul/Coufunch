import XCTest
@testable import Coufunch

final class EarlyDepartureTests: XCTestCase {
    private func date(_ minute: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(minute * 60))
    }

    func testHourlyEarlyDepartureUsesActualMinutes() throws {
        let session = WorkSession(
            workplaceID: UUID(), startAt: date(0), endAt: date(125),
            status: .completed, payMode: .customHourly,
            hourlyRateSnapshot: 12_000,
            scheduledEndAt: date(180)
        )
        let result = try WorkPayCalculator.calculate(
            session: session, breaks: [], calendar: .current,
            nightPremiumEnabled: false, overtimePremiumEnabled: false
        )
        XCTAssertTrue(session.isEarlyDeparture)
        XCTAssertEqual(result.workedMinutes, 125)
        XCTAssertEqual(result.total, 25_000)
    }

    func testFixedDailyEarlyDepartureIsProrated() throws {
        let session = WorkSession(
            workplaceID: UUID(), startAt: date(0), endAt: date(120),
            status: .completed, payMode: .fixedDaily,
            fixedDailyPaySnapshot: 90_000,
            scheduledEndAt: date(180)
        )
        let result = try WorkPayCalculator.calculate(
            session: session, breaks: [], calendar: .current
        )
        XCTAssertEqual(result.total, 60_000)
    }

    func testFullShiftFixedDailyPayUnchanged() throws {
        let session = WorkSession(
            workplaceID: UUID(), startAt: date(0), endAt: date(180),
            status: .completed, payMode: .fixedDaily,
            fixedDailyPaySnapshot: 90_000
        )
        let result = try WorkPayCalculator.calculate(
            session: session, breaks: [], calendar: .current
        )
        XCTAssertFalse(session.isEarlyDeparture)
        XCTAssertEqual(result.total, 90_000)
    }

    func testEarlyDepartureDoesNotQualifyForAutomaticAttendanceIncentive() {
        let workplace = UUID()
        let session = WorkSession(
            workplaceID: workplace, startAt: date(0), endAt: date(120),
            status: .completed, scheduledEndAt: date(180)
        )
        XCTAssertTrue(WorkAttendance.uniqueDays(
            of: [session], workplaceID: workplace, calendar: .current
        ).isEmpty)
    }
}

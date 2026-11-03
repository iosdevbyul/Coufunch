import XCTest
@testable import Coufunch

final class PaydayReminderDateTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return value
    }
    private func date(_ day: Int, _ hour: Int = 19) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    func testWeekdayShiftSchedulesFollowingBusinessDayAtTwoPM() {
        let result = PaydayReminderDate.nextBusinessDay(after: date(19),
            holidays: [], loadedYears: [2026])
        XCTAssertEqual(result, date(20, 14))
    }

    func testFridayShiftRollsForwardToMonday() {
        let result = PaydayReminderDate.nextBusinessDay(after: date(16),
            holidays: [], loadedYears: [2026])
        XCTAssertEqual(result, date(19, 14))
    }

    func testHolidayOnMondayRollsForwardToTuesday() {
        let result = PaydayReminderDate.nextBusinessDay(after: date(16),
            holidays: ["2026-10-19"], loadedYears: [2026])
        XCTAssertEqual(result, date(20, 14))
    }

    func testMissingHolidayYearDoesNotSchedulePotentiallyWrongPayday() {
        XCTAssertNil(PaydayReminderDate.nextBusinessDay(after: date(19),
            holidays: [], loadedYears: []))
    }
    func testConfirmedShiftReminderOccursTwoHoursBeforeStart() {
        let shift = WorkSession(
            workplaceID: UUID(), startAt: date(20, 9),
            endAt: date(20, 18), status: .confirmed
        )
        let expected = date(20, 7)
        XCTAssertEqual(
            ConfirmedShiftReminderDate.dueDate(for: shift, now: date(19, 19)),
            expected
        )
    }

    func testOnlyConfirmedFutureShiftsProduceReminders() {
        let shift = WorkSession(
            workplaceID: UUID(), startAt: date(20, 9),
            endAt: date(20, 18), status: .applied
        )
        XCTAssertNil(ConfirmedShiftReminderDate.dueDate(for: shift, now: date(19, 19)))
        shift.status = .completed
        XCTAssertNil(ConfirmedShiftReminderDate.dueDate(for: shift, now: date(19, 19)))
        shift.status = .confirmed
        XCTAssertNil(ConfirmedShiftReminderDate.dueDate(for: shift, now: date(20, 8)))
    }

    func testRescheduledShiftUsesUpdatedStartTime() {
        let shift = WorkSession(
            workplaceID: UUID(), startAt: date(20, 9),
            endAt: date(20, 18), status: .confirmed
        )
        shift.startAt = date(20, 11)
        XCTAssertEqual(
            ConfirmedShiftReminderDate.dueDate(for: shift, now: date(19, 19)),
            date(20, 9)
        )
    }

    func testReminderIsNotRescheduledAtOrAfterTwoHourBoundary() {
        let shift = WorkSession(
            workplaceID: UUID(), startAt: date(20, 9),
            endAt: date(20, 18), status: .confirmed
        )
        XCTAssertNil(ConfirmedShiftReminderDate.dueDate(for: shift, now: date(20, 7)))
        XCTAssertNil(ConfirmedShiftReminderDate.dueDate(for: shift, now: date(20, 8)))
    }

    func testOvernightShiftUsesStartTimeRatherThanEndTime() {
        let shift = WorkSession(
            workplaceID: UUID(), startAt: date(20, 23),
            endAt: date(21, 8), status: .confirmed
        )
        XCTAssertEqual(
            ConfirmedShiftReminderDate.dueDate(for: shift, now: date(20, 19)),
            date(20, 21)
        )
    }

    func testCancellingConfirmedShiftRemovesReminderEligibility() {
        let shift = WorkSession(
            workplaceID: UUID(), startAt: date(20, 9),
            endAt: date(20, 18), status: .confirmed
        )
        XCTAssertNotNil(ConfirmedShiftReminderDate.dueDate(for: shift, now: date(19, 19)))
        shift.status = .applied
        XCTAssertNil(ConfirmedShiftReminderDate.dueDate(for: shift, now: date(19, 19)))
    }

}

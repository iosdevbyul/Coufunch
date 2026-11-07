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


    func testFifthCompletedAttendanceDayAddsWeeklyHolidayPayOnce() {
        let workplace = Workplace(name: "Warehouse")
        let sessions = (11...16).map { day in
            WorkSession(workplaceID: workplace.id, startAt: date(day, 19), status: .completed)
        }
        let rules = [
            IncentiveRule(workplaceID: workplace.id, name: "Weekly holiday",
                          period: .weekly, requiredAttendanceDays: 5, amount: 82_560),
            IncentiveRule(workplaceID: workplace.id, name: "Six-day special",
                          period: .weekly, requiredAttendanceDays: 6, amount: 41_280)
        ]
        XCTAssertEqual(WeeklyHolidayPayReminder.amount(
            for: [sessions[4]], allSessions: sessions, workplaces: [workplace],
            rules: rules, calendar: calendar
        ), 82_560)
        XCTAssertEqual(WeeklyHolidayPayReminder.amount(
            for: [sessions[4], sessions[5]], allSessions: sessions,
            workplaces: [workplace], rules: rules, calendar: calendar
        ), 82_560)
        XCTAssertEqual(WeeklyHolidayPayReminder.amount(
            for: [sessions[5]], allSessions: sessions, workplaces: [workplace],
            rules: rules, calendar: calendar
        ), 0)
    }

    func testFourDaysOrUnpaidFifthDayDoesNotAddWeeklyHolidayPay() {
        let workplace = Workplace(name: "Warehouse")
        let sessions = (11...14).map { day in
            WorkSession(workplaceID: workplace.id, startAt: date(day, 19), status: .completed)
        }
        let rule = IncentiveRule(workplaceID: workplace.id, name: "Weekly holiday",
                                 period: .weekly, requiredAttendanceDays: 5, amount: 82_560)
        XCTAssertEqual(WeeklyHolidayPayReminder.amount(
            for: sessions, allSessions: sessions, workplaces: [workplace],
            rules: [rule], calendar: calendar
        ), 0)
        let fifth = WorkSession(workplaceID: workplace.id,
                                startAt: date(15, 19), status: .confirmed)
        XCTAssertEqual(WeeklyHolidayPayReminder.amount(
            for: [fifth], allSessions: sessions + [fifth],
            workplaces: [workplace], rules: [rule], calendar: calendar
        ), 0)
    }

    func testPreviouslyPaidFifthDayDoesNotAddAllowanceToSixthDayReminder() {
        let workplace = Workplace(name: "Warehouse")
        let sessions = (11...16).map { day in
            WorkSession(workplaceID: workplace.id, startAt: date(day, 19), status: .completed)
        }
        let rule = IncentiveRule(workplaceID: workplace.id, name: "Weekly holiday",
                                 period: .weekly, requiredAttendanceDays: 5, amount: 82_560)
        XCTAssertEqual(WeeklyHolidayPayReminder.amount(
            for: [sessions[5]], allSessions: sessions, workplaces: [workplace],
            rules: [rule], calendar: calendar
        ), 0)
    }
}

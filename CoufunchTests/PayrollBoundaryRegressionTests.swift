import XCTest
import SwiftData
@testable import Coufunch

@MainActor
final class PayrollBoundaryRegressionTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Seoul")!
        value.firstWeekday = 1
        return value
    }

    private func day(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day,
                                           hour: hour, minute: minute))!
    }

    func testTwoBreaksAcrossMidnightAreExcludedFromNightHours() throws {
        let start = day(2026, 10, 19, 20)
        let end = day(2026, 10, 20, 4)
        let shift = WorkSession(workplaceID: UUID(), startAt: start, endAt: end,
                                status: .completed, hourlyRateSnapshot: 10_320)
        let rest = [
            WorkBreak(sessionID: shift.id, startAt: day(2026, 10, 19, 22),
                      endAt: day(2026, 10, 19, 23)),
            WorkBreak(sessionID: shift.id, startAt: day(2026, 10, 20, 2),
                      endAt: day(2026, 10, 20, 3))
        ]
        let pay = try WorkPayCalculator.calculate(session: shift, breaks: rest, calendar: calendar)
        XCTAssertEqual(pay.workedMinutes, 360)
        XCTAssertEqual(pay.nightMinutes, 240)
        XCTAssertEqual(pay.overtimeMinutes, 0)
        XCTAssertEqual(pay.basePay, 61_920)
        XCTAssertEqual(pay.nightPremium, 20_640)
        XCTAssertEqual(pay.total, 82_560)
    }

    func testOverlappingBreaksAreNotSubtractedTwice() throws {
        let shift = WorkSession(workplaceID: UUID(), startAt: day(2026, 10, 19, 8),
                                endAt: day(2026, 10, 19, 18), hourlyRateSnapshot: 10_320)
        let rests = [
            WorkBreak(sessionID: shift.id, startAt: day(2026, 10, 19, 12),
                      endAt: day(2026, 10, 19, 13)),
            WorkBreak(sessionID: shift.id, startAt: day(2026, 10, 19, 12, 30),
                      endAt: day(2026, 10, 19, 13, 30))
        ]
        let pay = try WorkPayCalculator.calculate(session: shift, breaks: rests, calendar: calendar)
        XCTAssertEqual(pay.workedMinutes, 510)
        XCTAssertEqual(pay.overtimeMinutes, 30)
        XCTAssertEqual(pay.basePay, 87_720)
        XCTAssertEqual(pay.overtimePremium, 2_580)
    }

    func testOutOfRangeBreakFailsInsteadOfReducingPay() {
        let shift = WorkSession(workplaceID: UUID(), startAt: day(2026, 10, 19, 8),
                                endAt: day(2026, 10, 19, 17), hourlyRateSnapshot: 10_320)
        let rest = WorkBreak(sessionID: shift.id,
                             startAt: day(2026, 10, 19, 7),
                             endAt: day(2026, 10, 19, 8))
        XCTAssertThrowsError(try WorkPayCalculator.calculate(
            session: shift, breaks: [rest], calendar: calendar
        )) { error in
            XCTAssertEqual(error as? PayCalculationError, .invalidBreak)
        }
    }

    func testMinimumWageChangesAtCalendarYearBoundaryWithoutChangingOldSnapshots() {
        let before = day(2026, 12, 31, 23)
        let after = day(2027, 1, 1, 0)
        XCTAssertEqual(MinimumWageSchedule.hourlyRate(for: before, calendar: calendar), 10_320)
        XCTAssertEqual(MinimumWageSchedule.hourlyRate(for: after, calendar: calendar), 10_700)
        XCTAssertNil(MinimumWageSchedule.hourlyRate(
            for: day(2028, 1, 1, 0), calendar: calendar
        ))
        let recorded = WorkSession(workplaceID: UUID(), startAt: before,
                                   endAt: day(2027, 1, 1, 7),
                                   hourlyRateSnapshot: 10_320)
        XCTAssertEqual(recorded.hourlyRateSnapshot, 10_320)
    }

    func testOvernightAttendanceBelongsToStartDateAndNotNextDay() {
        let workplace = Workplace(name: "Sample")
        let shift = WorkSession(workplaceID: workplace.id,
            startAt: day(2026, 10, 19, 23), endAt: day(2026, 10, 20, 5),
            status: .completed, hourlyRateSnapshot: 10_320)
        let dates = WorkAttendance.uniqueDays(
            of: [shift], workplaceID: workplace.id, calendar: calendar
        )
        XCTAssertEqual(dates.count, 1)
        XCTAssertTrue(dates.contains(calendar.startOfDay(for: day(2026, 10, 19, 0))))
        XCTAssertFalse(dates.contains(calendar.startOfDay(for: day(2026, 10, 20, 0))))
    }

    func testOldWorkSessionSnapshotsPersistAfterStoreReload() throws {
        let schema = Schema([Workplace.self, WorkplacePaySettings.self, WorkSession.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let id = UUID()
        let workplace = Workplace(name: "Sample")
        let setting = WorkplacePaySettings(workplaceID: workplace.id,
            payMode: .customHourly, customHourlyRate: 15_000)
        let shift = WorkSession(id: id, workplaceID: workplace.id,
            startAt: day(2026, 10, 19, 9), endAt: day(2026, 10, 19, 18),
            status: .completed, payMode: .customHourly,
            hourlyRateSnapshot: 12_000,
            nightPremiumSnapshot: false, overtimePremiumSnapshot: true)
        context.insert(workplace)
        context.insert(setting)
        context.insert(shift)
        try context.save()

        setting.customHourlyRate = 20_000
        setting.overtimePremiumEnabled = false
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<WorkSession>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.id, id)
        XCTAssertEqual(fetched.first?.hourlyRateSnapshot, 12_000)
        XCTAssertEqual(fetched.first?.nightPremiumSnapshot, false)
        XCTAssertEqual(fetched.first?.overtimePremiumSnapshot, true)
    }
}

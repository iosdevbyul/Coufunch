import XCTest
@testable import Coufunch

final class EstimatedTakeHomeCalculatorTests: XCTestCase {
    func testUsesFixedRateWithoutDayCountRules() {
        let seven = EstimatedTakeHomeCalculator.calculate(gross: 700_000, shifts: [])
        XCTAssertEqual(seven.deductions, 68_022)
        XCTAssertEqual(seven.net, 631_978)
        XCTAssertEqual(seven.outstanding, 0)
    }

    func testGrossEqualsNetPlusDeductionsExactly() {
        let result = EstimatedTakeHomeCalculator.calculate(gross: 1_461_600, shifts: [])
        XCTAssertEqual(result.deductions, 142_029)
        XCTAssertEqual(result.net, 1_319_571)
        XCTAssertEqual(result.net + result.deductions, 1_461_600)
    }

    func testZeroGross() {
        let result = EstimatedTakeHomeCalculator.calculate(gross: 0, shifts: [])
        XCTAssertEqual(result.net, 0)
        XCTAssertEqual(result.deductions, 0)
    }
    func testFirstSevenDaysShowEmploymentOnlyAndFullInsuranceComparison() {
        for day in 1...7 {
            let comparison = EarlyWorkdayPayComparison.estimates(gross: 108_000, dayNumber: day)
            XCTAssertEqual(comparison?.employmentOnly, 107_028)
            XCTAssertEqual(comparison?.allInsurance, 97_505)
        }
    }

    func testEighthDayDoesNotShowEarlyComparison() {
        XCTAssertNil(EarlyWorkdayPayComparison.estimates(gross: 108_000, dayNumber: 8))
        XCTAssertNil(EarlyWorkdayPayComparison.estimates(gross: 108_000, dayNumber: 0))
    }

    func testAttendanceUsesUniqueCompletedDaysPerWorkplaceAndResetsMonthly() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        func date(_ day: Int, month: Int = 11) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 9))!
        }

        let workplace = UUID()
        let anotherWorkplace = UUID()
        let first = WorkSession(workplaceID: workplace, startAt: date(1),
                                endAt: date(1).addingTimeInterval(3600), status: .completed)
        let duplicate = WorkSession(workplaceID: workplace, startAt: date(1).addingTimeInterval(7200),
                                    endAt: date(1).addingTimeInterval(10800), status: .completed)
        let other = WorkSession(workplaceID: anotherWorkplace, startAt: date(2),
                                endAt: date(2).addingTimeInterval(3600), status: .completed)
        let applied = WorkSession(workplaceID: workplace, startAt: date(2),
                                  status: .applied)
        let third = WorkSession(workplaceID: workplace, startAt: date(3),
                                endAt: date(3).addingTimeInterval(3600), status: .completed)
        let december = WorkSession(workplaceID: workplace, startAt: date(1, month: 12),
                                   endAt: date(1, month: 12).addingTimeInterval(3600),
                                   status: .completed)
        let all = [first, duplicate, other, applied, third, december]
        XCTAssertEqual(EarlyWorkdayPayComparison.attendanceDayNumber(
            for: duplicate, sessions: all, calendar: calendar
        ), 1)
        XCTAssertEqual(EarlyWorkdayPayComparison.attendanceDayNumber(
            for: third, sessions: all, calendar: calendar
        ), 2)
        XCTAssertEqual(EarlyWorkdayPayComparison.attendanceDayNumber(
            for: december, sessions: all, calendar: calendar
        ), 1)
        XCTAssertNil(EarlyWorkdayPayComparison.attendanceDayNumber(
            for: applied, sessions: all, calendar: calendar
        ))
    }

}

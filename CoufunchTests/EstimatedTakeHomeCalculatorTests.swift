import XCTest
@testable import Coufunch

final class EstimatedTakeHomeCalculatorTests: XCTestCase {
    private func shifts(_ count: Int) -> [EstimatedShiftGross] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1))!
        return (0..<count).map { index in
            EstimatedShiftGross(date: calendar.date(byAdding: .day, value: index, to: start)!,
                                gross: 100_000)
        }
    }

    func testBeforeEighthDayUsesOnlyEmploymentInsuranceEstimate() {
        let result = EstimatedTakeHomeCalculator.calculate(gross: 700_000, shifts: shifts(7))
        XCTAssertEqual(result.deductions, 6_300)
        XCTAssertEqual(result.net, 693_700)
    }

    func testEighthDayCapsCatchUpDeductionAndCarriesBalance() {
        let result = EstimatedTakeHomeCalculator.calculate(gross: 800_000, shifts: shifts(8))
        XCTAssertEqual(result.deductions, 66_300)
        XCTAssertGreaterThan(result.outstanding, 0)
        XCTAssertEqual(result.net, 733_700)
    }

    func testNinthDayContinuesCollectingOutstandingInsurance() {
        let eight = EstimatedTakeHomeCalculator.calculate(gross: 800_000, shifts: shifts(8))
        let nine = EstimatedTakeHomeCalculator.calculate(gross: 900_000, shifts: shifts(9))
        XCTAssertGreaterThan(nine.deductions, eight.deductions)
        XCTAssertLessThanOrEqual(nine.deductions - eight.deductions, 60_000)
        XCTAssertLessThan(nine.outstanding, eight.outstanding)
    }

    func testTwoShiftsOnSameDateCountAsOneAttendanceDay() {
        let eight = shifts(8)
        let oneSplit = eight.dropLast() + [
            EstimatedShiftGross(date: eight.last!.date, gross: 50_000),
            EstimatedShiftGross(date: eight.last!.date, gross: 50_000)
        ]
        let result = EstimatedTakeHomeCalculator.calculate(gross: 800_000, shifts: Array(oneSplit))
        XCTAssertEqual(result.deductions, 66_300)
    }
}

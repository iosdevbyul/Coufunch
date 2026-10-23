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
        XCTAssertEqual(result.deductions, 142_021)
        XCTAssertEqual(result.net, 1_319_579)
        XCTAssertEqual(result.net + result.deductions, 1_461_600)
    }

    func testZeroGross() {
        let result = EstimatedTakeHomeCalculator.calculate(gross: 0, shifts: [])
        XCTAssertEqual(result.net, 0)
        XCTAssertEqual(result.deductions, 0)
    }
}

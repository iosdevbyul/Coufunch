import XCTest
@testable import Coufunch

final class InsuranceEstimateComparisonTests: XCTestCase {
    func testCompleteProfileShowsDeductionDifference() {
        let gross = Decimal(1_000_000)
        let profile = DailyWorkerInsuranceEstimator.estimate(
            gross: gross, pensionEnrollment: .notEnrolled,
            healthEnrollment: .notEnrolled
        )
        let comparison = InsuranceEstimateComparison.calculate(
            gross: gross, profile: profile
        )
        let legacy = EstimatedTakeHomeCalculator.calculate(gross: gross, shifts: [])
        XCTAssertEqual(comparison.profileDeductions, Decimal(9_000))
        XCTAssertEqual(comparison.deductionDifference, Decimal(9_000) - legacy.deductions)
        XCTAssertEqual(comparison.profileNet, Decimal(991_000))
        XCTAssertEqual(comparison.flatRateDeductions, legacy.deductions)
    }

    func testUnknownEnrollmentDoesNotInventDifference() {
        let gross = Decimal(1_000_000)
        let profile = DailyWorkerInsuranceEstimator.estimate(
            gross: gross, pensionEnrollment: .unknown,
            healthEnrollment: .notEnrolled
        )
        let comparison = InsuranceEstimateComparison.calculate(
            gross: gross, profile: profile
        )
        XCTAssertNil(comparison.profileDeductions)
        XCTAssertNil(comparison.deductionDifference)
        XCTAssertNil(comparison.profileNet)
    }
}

import XCTest
@testable import Coufunch

final class DailyWorkerInsuranceEstimatorTests: XCTestCase {
    func testHealthEligibilityRequiresEightDaysAndEmploymentContinuity() {
        let date = Date(timeIntervalSince1970: 1_780_000_000)
        XCTAssertEqual(DailyWorkerHealthEligibility.evaluate(.init(
            month: date, attendanceDays: 7, employedPreviousMonth: true,
            startedOnFirstDay: false)), .notEnrolled)
        XCTAssertEqual(DailyWorkerHealthEligibility.evaluate(.init(
            month: date, attendanceDays: 8, employedPreviousMonth: true,
            startedOnFirstDay: false)), .enrolled)
        XCTAssertEqual(DailyWorkerHealthEligibility.evaluate(.init(
            month: date, attendanceDays: 8, employedPreviousMonth: false,
            startedOnFirstDay: true)), .enrolled)
        XCTAssertEqual(DailyWorkerHealthEligibility.evaluate(.init(
            month: date, attendanceDays: 12, employedPreviousMonth: false,
            startedOnFirstDay: false)), .notEnrolled)
        XCTAssertEqual(DailyWorkerHealthEligibility.evaluate(.init(
            month: date, attendanceDays: 12, employedPreviousMonth: nil,
            startedOnFirstDay: false)), .unknown)
    }

    func testEmploymentInsuranceAppliesWithoutHealthOrPensionEnrollment() {
        let result = DailyWorkerInsuranceEstimator.estimate(
            gross: 1_000_000, pensionEnrollment: .notEnrolled,
            healthEnrollment: .notEnrolled)
        XCTAssertEqual(result.employment, 9_000)
        XCTAssertEqual(result.pension, 0)
        XCTAssertEqual(result.health, 0)
        XCTAssertEqual(result.longTermCare, 0)
        XCTAssertEqual(result.totalDeductions, 9_000)
        XCTAssertEqual(result.estimatedNet, 991_000)
    }

    func testEnrolledRequiresContributionBasesRatherThanAssumingGross() {
        let unknown = DailyWorkerInsuranceEstimator.estimate(
            gross: 1_000_000, pensionEnrollment: .enrolled,
            healthEnrollment: .enrolled)
        XCTAssertNil(unknown.estimatedNet)
        let known = DailyWorkerInsuranceEstimator.estimate(
            gross: 1_000_000, pensionEnrollment: .enrolled,
            healthEnrollment: .enrolled, pensionBase: 800_000, healthBase: 900_000)
        XCTAssertEqual(known.pension, 38_000)
        XCTAssertEqual(known.health, 32_355)
        XCTAssertEqual(known.longTermCare, 4_252)
        XCTAssertEqual(known.employment, 9_000)
        XCTAssertEqual(known.totalDeductions, 83_607)
        XCTAssertEqual(known.estimatedNet, 916_393)
    }

    func testUnknownEnrollmentDoesNotInventTakeHome() {
        let result = EstimatedTakeHomeCalculator.calculate(
            gross: 1_000_000, shifts: [], pensionEnrollment: .unknown,
            healthEnrollment: .notEnrolled)
        XCTAssertNil(result)
    }
}

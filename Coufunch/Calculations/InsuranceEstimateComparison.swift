import Foundation

/// Side-by-side informational estimate. No receipt or reconciliation is changed.
/// Neither estimate includes income tax, and the two methods are not interchangeable.
struct InsuranceEstimateComparison {
    let flatRateDeductions: Decimal
    let profileDeductions: Decimal?
    let deductionDifference: Decimal?
    let profileNet: Decimal?

    static func calculate(
        gross: Decimal,
        profile: DailyWorkerInsuranceBreakdown
    ) -> InsuranceEstimateComparison {
        let legacy = EstimatedTakeHomeCalculator.calculate(gross: gross, shifts: [])
        let profileDeductions = profile.totalDeductions
        return InsuranceEstimateComparison(
            flatRateDeductions: legacy.deductions,
            profileDeductions: profileDeductions,
            deductionDifference: profileDeductions.map { $0 - legacy.deductions },
            profileNet: profile.estimatedNet
        )
    }
}

import Foundation

struct EstimatedShiftGross {
    let date: Date
    let gross: Decimal
}

struct EstimatedTakeHomeResult {
    let net: Decimal
    let deductions: Decimal
    let outstanding: Decimal
}

/// Simplified 2026 employee social insurance estimate, not a payroll statement.
/// Pension 4.75%, health 3.595%, long-term care 13.14% of health,
/// and employment insurance 0.9%, totaling 9.717383%.
enum EstimatedTakeHomeCalculator {
    static let deductionRate = Decimal(string: "0.09717383")!

    /// Insurance-aware alternative. Unknown enrollment or missing contribution
    /// bases produce nil rather than an invented take-home amount.
    static func calculate(
        gross: Decimal,
        shifts: [EstimatedShiftGross],
        pensionEnrollment: InsuranceEnrollment,
        healthEnrollment: InsuranceEnrollment,
        pensionBase: Decimal? = nil,
        healthBase: Decimal? = nil,
        employmentBase: Decimal? = nil
    ) -> EstimatedTakeHomeResult? {
        let breakdown = DailyWorkerInsuranceEstimator.estimate(
            gross: gross, pensionEnrollment: pensionEnrollment,
            healthEnrollment: healthEnrollment, pensionBase: pensionBase,
            healthBase: healthBase, employmentBase: employmentBase
        )
        guard let deductions = breakdown.totalDeductions,
              let net = breakdown.estimatedNet else { return nil }
        return EstimatedTakeHomeResult(net: net, deductions: deductions, outstanding: 0)
    }

    static func calculate(gross: Decimal, shifts: [EstimatedShiftGross]) -> EstimatedTakeHomeResult {
        let taxableGross = max(Decimal.zero, gross)
        var rawDeduction = taxableGross * deductionRate
        var roundedDeduction = Decimal.zero
        NSDecimalRound(&roundedDeduction, &rawDeduction, 0, .plain)
        let deduction = min(taxableGross, roundedDeduction)
        return EstimatedTakeHomeResult(
            net: taxableGross - deduction,
            deductions: deduction,
            outstanding: 0
        )
    }
}

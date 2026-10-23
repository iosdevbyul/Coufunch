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

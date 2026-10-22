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

/// Approximation of the described Coupang daily deduction settlement, not a payslip.
/// A completed workday is one unique Korea-local start date.
enum EstimatedTakeHomeCalculator {
    static func calculate(gross: Decimal, shifts: [EstimatedShiftGross]) -> EstimatedTakeHomeResult {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let grouped = Dictionary(grouping: shifts) { calendar.startOfDay(for: $0.date) }
        let daily = grouped.map { (date: $0.key, gross: $0.value.reduce(Decimal.zero) { $0 + $1.gross }) }
            .sorted { $0.date < $1.date }
        // Approximate 2026 employee rates. Daily/monthly eligibility and payroll bases can differ.
        let employmentRate = Decimal(string: "0.009")!
        let pensionAndHealthRate = Decimal(string: "0.0475")!
            + Decimal(string: "0.03595")!
            + Decimal(string: "0.03595")! * Decimal(string: "0.1314")!
        let dailyCap: Decimal = 60_000
        var cumulativeGross: Decimal = 0
        var outstanding: Decimal = 0
        var collected: Decimal = 0
        for (index, item) in daily.enumerated() {
            cumulativeGross += item.gross
            outstanding += item.gross * employmentRate
            if index == 7 {
                outstanding += cumulativeGross * pensionAndHealthRate
            } else if index > 7 {
                outstanding += item.gross * pensionAndHealthRate
            }
            let withheld = min(outstanding, min(dailyCap, item.gross))
            outstanding -= withheld
            collected += withheld
        }
        // Incentives or other gross components not attributable to the shift are left
        // unadjusted rather than pretending to know their withholding schedule.
        return EstimatedTakeHomeResult(net: max(0, gross - collected),
                                       deductions: collected, outstanding: outstanding)
    }
}

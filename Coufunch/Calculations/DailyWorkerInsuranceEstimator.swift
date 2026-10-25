import Foundation

/// An estimate, not an employer enrollment decision or an official pay statement.
enum InsuranceEnrollment: Equatable {
    case enrolled
    case notEnrolled
    case unknown
}

struct DailyWorkerInsuranceContext {
    let month: Date
    let attendanceDays: Int
    /// Confirmed employment in the preceding month, not merely a saved shift.
    let employedPreviousMonth: Bool?
    /// Whether the worker started employment on day 1 of this month.
    let startedOnFirstDay: Bool?
}

/// Employer-reported health enrollment screening rule. A month with at least
/// eight attendance days alone is insufficient for a positive determination.
enum DailyWorkerHealthEligibility {
    static func evaluate(_ context: DailyWorkerInsuranceContext) -> InsuranceEnrollment {
        guard context.attendanceDays >= 8 else { return .notEnrolled }
        if context.employedPreviousMonth == true || context.startedOnFirstDay == true {
            return .enrolled
        }
        if context.employedPreviousMonth == false && context.startedOnFirstDay == false {
            return .notEnrolled
        }
        return .unknown
    }
}

struct DailyWorkerInsuranceBreakdown {
    let gross: Decimal
    let pension: Decimal?
    let health: Decimal?
    let longTermCare: Decimal?
    let employment: Decimal
    /// Nil until pension/health enrollment is explicitly known.
    let totalDeductions: Decimal?
    let estimatedNet: Decimal?
}

/// 2026 employee-side *illustrative* rates supplied for this payroll profile.
/// Pension and health contribution bases are externally reported remuneration,
/// which can differ from app-computed gross pay. No income tax is modeled here.
enum DailyWorkerInsuranceEstimator {
    static let pensionRate = Decimal(string: "0.0475")!
    static let healthRate = Decimal(string: "0.03595")!
    static let longTermCareOfHealthRate = Decimal(string: "0.1314")!
    static let employmentRate = Decimal(string: "0.009")!

    static func estimate(
        gross: Decimal,
        pensionEnrollment: InsuranceEnrollment,
        healthEnrollment: InsuranceEnrollment,
        pensionBase: Decimal? = nil,
        healthBase: Decimal? = nil,
        employmentBase: Decimal? = nil
    ) -> DailyWorkerInsuranceBreakdown {
        let gross = max(Decimal.zero, gross)
        let employment = rounded(max(Decimal.zero, employmentBase ?? gross) * employmentRate)
        let pension = component(enrollment: pensionEnrollment, base: pensionBase, rate: pensionRate)
        let health = component(enrollment: healthEnrollment, base: healthBase, rate: healthRate)
        let longTermCare = health.map { rounded($0 * longTermCareOfHealthRate) }
        let total: Decimal?
        if let pension, let health, let longTermCare {
            total = pension + health + longTermCare + employment
        } else {
            total = nil
        }
        return DailyWorkerInsuranceBreakdown(
            gross: gross, pension: pension, health: health,
            longTermCare: longTermCare, employment: employment,
            totalDeductions: total, estimatedNet: total.map { gross - $0 }
        )
    }

    private static func component(
        enrollment: InsuranceEnrollment, base: Decimal?, rate: Decimal
    ) -> Decimal? {
        switch enrollment {
        case .notEnrolled: return .zero
        case .unknown: return nil
        case .enrolled:
            guard let base else { return nil }
            return rounded(max(Decimal.zero, base) * rate)
        }
    }

    private static func rounded(_ amount: Decimal) -> Decimal {
        var raw = amount
        var rounded = Decimal.zero
        NSDecimalRound(&rounded, &raw, 0, .plain)
        return rounded
    }
}

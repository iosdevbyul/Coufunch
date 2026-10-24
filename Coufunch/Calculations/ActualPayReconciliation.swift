import Foundation

enum ActualPayReconciliation {
    /// Each actual deposit replaces its shift estimate. A bonus is removed from
    /// the remaining estimate only when the user explicitly confirms inclusion.
    static func total(estimatedMonthlyNet: Decimal,
                      shiftGross: [(id: UUID, gross: Decimal)],
                      actualBySession: [UUID: Decimal],
                      bonusNetBySession: [UUID: Decimal] = [:],
                      bonusInclusionBySession: [UUID: BonusInclusion] = [:]) -> Decimal {
        shiftGross.reduce(estimatedMonthlyNet) { running, shift in
            guard let actual = actualBySession[shift.id] else { return running }
            let estimated = EstimatedTakeHomeCalculator.calculate(
                gross: shift.gross, shifts: [.init(date: .now, gross: shift.gross)]
            ).net
            let includedBonus = bonusInclusionBySession[shift.id] == .included
                ? (bonusNetBySession[shift.id] ?? 0) : 0
            return running - estimated - includedBonus + actual
        }
    }
}

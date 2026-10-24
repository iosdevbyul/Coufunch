import Foundation

enum ActualPayReconciliation {
    static func total(estimatedMonthlyNet: Decimal,
                      shiftGross: [(id: UUID, gross: Decimal)],
                      actualBySession: [UUID: Decimal]) -> Decimal {
        shiftGross.reduce(estimatedMonthlyNet) { running, shift in
            guard let actual = actualBySession[shift.id] else { return running }
            let estimated = EstimatedTakeHomeCalculator.calculate(
                gross: shift.gross, shifts: [.init(date: .now, gross: shift.gross)]
            ).net
            return running - estimated + actual
        }
    }
}

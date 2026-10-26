import Foundation

/// Compare a complete monthly net bank receipt against two *unreconciled*
/// estimates. Neither estimate includes income tax. Never extrapolate from
/// daily deposits or separately paid allowances.
struct MonthlyReceiptEstimateValidation {
    let actualNet: Decimal
    let flatRateNet: Decimal
    let profileNet: Decimal?
    /// Estimate minus actual. Positive means that the estimate is too high.
    let flatRateError: Decimal
    let profileError: Decimal?
    let flatRateAbsoluteError: Decimal
    let profileAbsoluteError: Decimal?

    static func calculate(
        month: Date,
        workplaceID: UUID,
        receipts: [ReceivedPayRecord],
        gross: Decimal,
        hasIncentives: Bool,
        profileNet: Decimal?,
        calendar: Calendar
    ) -> MonthlyReceiptEstimateValidation? {
        guard let interval = calendar.dateInterval(of: .month, for: month) else {
            return nil
        }
        let scoped = receipts.filter { interval.contains($0.monthStart) }
        // An eligible comparison must be a single, explicitly identified
        // full-month net receipt, with no additional daily or allowance items.
        guard scoped.count == 1, let receipt = scoped.first,
              receipt.workplaceID == workplaceID,
              receipt.sessionID == nil,
              receipt.allowanceAwardID == nil,
              receipt.basis == .net,
              receipt.amount >= 0,
              (!hasIncentives || receipt.bonusInclusion == .included) else {
            return nil
        }
        let flatRateNet = EstimatedTakeHomeCalculator.calculate(
            gross: gross, shifts: []
        ).net
        let flatRateError = flatRateNet - receipt.amount
        let profileError = profileNet.map { $0 - receipt.amount }
        return MonthlyReceiptEstimateValidation(
            actualNet: receipt.amount,
            flatRateNet: flatRateNet,
            profileNet: profileNet,
            flatRateError: flatRateError,
            profileError: profileError,
            flatRateAbsoluteError: abs(flatRateError),
            profileAbsoluteError: profileError.map { abs($0) }
        )
    }
}

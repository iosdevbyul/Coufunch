import Foundation

struct PayForecast {
    let completedGross: Decimal
    let confirmedGross: Decimal
    let appliedGross: Decimal
    let completedCount: Int
    let confirmedCount: Int
    let appliedCount: Int
    let unpricedCount: Int

    var securedGross: Decimal { completedGross + confirmedGross }
    var possibleGross: Decimal { securedGross + appliedGross }
}

struct PayReconciliation {
    let estimatedGross: Decimal
    let receivedAmount: Decimal
    var difference: Decimal { receivedAmount - estimatedGross }
}

/// Forecasted session pay is kept apart by status. Applied shifts are hypothetical,
/// confirmed shifts are projected and only completed shifts belong to earned gross.
enum PayForecastCalculator {
    static func calculate(
        month: Date,
        sessions: [WorkSession],
        breaks: [WorkBreak],
        settings: [WorkplacePaySettings],
        calendar: Calendar,
        holidayDates: Set<String> = []
    ) -> PayForecast {
        guard let interval = calendar.dateInterval(of: .month, for: month) else {
            return PayForecast(completedGross: 0, confirmedGross: 0, appliedGross: 0,
                               completedCount: 0, confirmedCount: 0, appliedCount: 0,
                               unpricedCount: 0)
        }
        var completed: Decimal = 0
        var confirmed: Decimal = 0
        var applied: Decimal = 0
        var completeCount = 0
        var confirmCount = 0
        var applyCount = 0
        var unpriced = 0

        for session in sessions where interval.contains(session.startAt) {
            let setting = settings.first { $0.workplaceID == session.workplaceID }
            do {
                let pay = try WorkPayCalculator.calculate(
                    session: session,
                    breaks: breaks.filter { $0.sessionID == session.id },
                    calendar: calendar,
                    nightPremiumEnabled: session.nightPremiumSnapshot ?? setting?.nightPremiumEnabled ?? true,
                    overtimePremiumEnabled: session.overtimePremiumSnapshot ?? setting?.overtimePremiumEnabled ?? true,
                    holidayPaidMinutes: HolidayWorkMinutes.calculate(session: session,
                        breaks: breaks.filter { $0.sessionID == session.id }, holidayDates: holidayDates)
                )
                switch session.status {
                case .completed:
                    completed += pay.total
                    completeCount += 1
                case .confirmed:
                    confirmed += pay.total
                    confirmCount += 1
                case .applied:
                    applied += pay.total
                    applyCount += 1
                }
            } catch {
                unpriced += 1
            }
        }
        return PayForecast(completedGross: completed, confirmedGross: confirmed,
                           appliedGross: applied, completedCount: completeCount,
                           confirmedCount: confirmCount, appliedCount: applyCount,
                           unpricedCount: unpriced)
    }
}

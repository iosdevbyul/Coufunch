import Foundation

enum PayCalculationError: Error, Equatable {
    case missingEndTime
    case invalidTimeRange
    case missingHourlyRate
    case missingFixedPay
    case invalidRate
    case invalidBreak
}

/// Monetary amounts are estimated gross KRW, before deductions.
/// The minimum wage is injected as a dated snapshot by the caller, never fetched implicitly.
struct PayBreak: Equatable {
    let start: Date
    let end: Date
}

struct PayResult: Equatable {
    let workedMinutes: Int
    let nightMinutes: Int
    let basePay: Decimal
    let nightPremium: Decimal
    let overtimeMinutes: Int
    let overtimePremium: Decimal
    let total: Decimal
}

enum WorkPayCalculator {
    static func calculate(
        session: WorkSession,
        breaks: [WorkBreak],
        calendar: Calendar,
        nightPremiumEnabled: Bool = true,
        overtimePremiumEnabled: Bool = true
    ) throws -> PayResult {
        guard let end = session.endAt else { throw PayCalculationError.missingEndTime }
        guard end > session.startAt else { throw PayCalculationError.invalidTimeRange }

        let intervals = try mergedBreaks(breaks.map { PayBreak(start: $0.startAt, end: $0.endAt) },
                                         start: session.startAt, end: end)
        let worked = minutesBetween(session.startAt, end) -
            intervals.reduce(0) { $0 + minutesBetween($1.start, $1.end) }

        let night = nightPremiumEnabled
            ? nightMinutes(start: session.startAt, end: end, breaks: intervals, calendar: calendar)
            : 0

        guard worked >= 0, night <= worked else { throw PayCalculationError.invalidBreak }

        // Daily overtime starts after eight paid hours, excluding unpaid breaks.
        // Holiday premiums and workplace eligibility are outside this estimate.
        let overtime = overtimePremiumEnabled ? max(0, worked - 8 * 60) : 0

        switch session.payMode {
        case .fixedDaily:
            guard let amount = session.fixedDailyPaySnapshot else { throw PayCalculationError.missingFixedPay }
            guard amount >= 0 else { throw PayCalculationError.invalidRate }
            return PayResult(workedMinutes: worked, nightMinutes: night,
                             basePay: amount, nightPremium: 0,
                             overtimeMinutes: overtime, overtimePremium: 0, total: amount)
        case .minimumHourly, .customHourly:
            guard let rate = session.hourlyRateSnapshot else { throw PayCalculationError.missingHourlyRate }
            guard rate >= 0 else { throw PayCalculationError.invalidRate }
            let base = rate * Decimal(worked) / 60
            let premium = nightPremiumEnabled ? rate * Decimal(night) / 120 : 0
            let overtimePremium = rate * Decimal(overtime) / 120
            return PayResult(workedMinutes: worked, nightMinutes: night,
                             basePay: base, nightPremium: premium,
                             overtimeMinutes: overtime, overtimePremium: overtimePremium,
                             total: base + premium + overtimePremium)
        }
    }

    /// Five-minute aligned intervals are required for predictable drag-to-select accounting.
    private static func minutesBetween(_ start: Date, _ end: Date) -> Int {
        Int((end.timeIntervalSince(start) / 60).rounded())
    }

    private static func mergedBreaks(_ breaks: [PayBreak], start: Date, end: Date) throws -> [PayBreak] {
        for item in breaks {
            guard item.start < item.end, item.start >= start, item.end <= end else {
                throw PayCalculationError.invalidBreak
            }
        }
        let sorted = breaks.sorted { $0.start < $1.start }
        var merged: [PayBreak] = []
        for item in sorted {
            if let last = merged.last, item.start <= last.end {
                merged[merged.count - 1] = PayBreak(start: last.start, end: max(last.end, item.end))
            } else {
                merged.append(item)
            }
        }
        return merged
    }

    private static func overlap(_ start: Date, _ end: Date, _ otherStart: Date, _ otherEnd: Date) -> Int {
        max(0, minutesBetween(max(start, otherStart), min(end, otherEnd)))
    }

    private static func nightMinutes(start: Date, end: Date, breaks: [PayBreak], calendar: Calendar) -> Int {
        // Iterate civil days, including the preceding day, because nighttime crosses midnight.
        var day = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -1, to: start)!)
        var total = 0
        while day < end {
            let components = calendar.dateComponents([.year, .month, .day], from: day)
            var twentyTwo = components
            twentyTwo.hour = 22
            twentyTwo.minute = 0
            var six = components
            six.hour = 6
            six.minute = 0
            if let nightStart = calendar.date(from: twentyTwo),
               let nextDay = calendar.date(byAdding: .day, value: 1, to: day),
               let nightEnd = calendar.date(byAdding: .hour, value: 6, to: nextDay) {
                total += overlap(start, end, nightStart, nightEnd)
                for rest in breaks {
                    total -= overlap(rest.start, rest.end, nightStart, nightEnd)
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { break }
            day = next
        }
        return max(0, total)
    }
}

struct IncentiveAward: Equatable {
    let ruleID: UUID
    let periodStart: Date
    let amount: Decimal
}

enum WorkIncentiveCalculator {
    static func awards(
        sessions: [WorkSession],
        rules: [IncentiveRule],
        workplace: Workplace,
        calendar baseCalendar: Calendar
    ) -> [IncentiveAward] {
        var calendar = baseCalendar
        calendar.firstWeekday = workplace.weekStartWeekday
        let days = WorkAttendance.uniqueDays(of: sessions, workplaceID: workplace.id, calendar: calendar)
        var result: [IncentiveAward] = []
        for rule in rules where rule.isEnabled && rule.workplaceID == workplace.id
            && rule.requiredAttendanceDays > 0 && rule.amount >= 0 {
            let component: Calendar.Component
            switch rule.period {
            case .daily: component = .day
            case .weekly: component = .weekOfYear
            case .monthly: component = .month
            }
            let grouped = Dictionary(grouping: days) {
                calendar.dateInterval(of: component, for: $0)?.start ?? calendar.startOfDay(for: $0)
            }
            for (start, dates) in grouped where dates.count >= rule.requiredAttendanceDays {
                result.append(IncentiveAward(ruleID: rule.id, periodStart: start, amount: rule.amount))
            }
        }
        // Nonstackable rules within one workplace and period compete: keep the largest.
        let rulesByID = Dictionary(uniqueKeysWithValues: rules.map { ($0.id, $0) })
        let nonStackable = result.filter { rulesByID[$0.ruleID]?.canStack == false }
        let stackable = result.filter { rulesByID[$0.ruleID]?.canStack != false }
        let best = Dictionary(grouping: nonStackable) { award in
            let rule = rulesByID[award.ruleID]!
            return "\(rule.period.rawValue):\(award.periodStart.timeIntervalSince1970)"
        }.values.compactMap { $0.max(by: { $0.amount < $1.amount }) }
        return (stackable + best).sorted { $0.periodStart < $1.periodStart }
    }

    static func manualTotal(_ incentives: [ManualIncentive], workplaceID: UUID) -> Decimal {
        incentives.filter { $0.workplaceID == workplaceID }.reduce(Decimal.zero) { $0 + $1.amount }
    }
}

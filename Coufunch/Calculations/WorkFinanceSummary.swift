import Foundation

struct MonthlyPaySummary {
    let completedDays: Int
    let basePay: Decimal
    let nightPremium: Decimal
    let overtimePremium: Decimal
    let holidayPremium: Decimal
    let automaticIncentives: Decimal
    let manualIncentives: Decimal
    let skippedSessions: Int

    var total: Decimal { basePay + nightPremium + overtimePremium + holidayPremium + automaticIncentives + manualIncentives }
    var dailyAverage: Decimal {
        guard completedDays > 0 else { return 0 }
        return NSDecimalNumber(decimal: total)
            .dividing(by: NSDecimalNumber(value: completedDays))
            .decimalValue
    }
}

struct NextWorkdayOpportunity: Identifiable {
    let id: UUID
    let workplaceName: String
    let ruleName: String
    let remainingDays: Int
    let amount: Decimal
    let periodEnd: Date
}

/// Incentive attribution: monthly awards belong to their calendar month;
/// weekly awards are attributed to the week-end date, not to the week-start.
/// This avoids losing Sunday–Saturday awards spanning two months.
enum WorkFinanceSummary {
    static func summarize(
        month: Date,
        sessions: [WorkSession],
        breaks: [WorkBreak],
        workplaces: [Workplace],
        settings: [WorkplacePaySettings],
        rules: [IncentiveRule],
        manual: [ManualIncentive],
        calendar: Calendar,
        holidayDates: Set<String> = []
    ) -> MonthlyPaySummary {
        guard let interval = calendar.dateInterval(of: .month, for: month) else {
            return MonthlyPaySummary(completedDays: 0, basePay: 0, nightPremium: 0, overtimePremium: 0, holidayPremium: 0,
                                     automaticIncentives: 0, manualIncentives: 0, skippedSessions: 0)
        }
        let included = sessions.filter { $0.status == .completed &&
            interval.contains($0.startAt) }
        var base: Decimal = 0
        var premium: Decimal = 0
        var overtimePremium: Decimal = 0
        var holidayPremium: Decimal = 0
        var skipped = 0
        for session in included {
            do {
                let nightEnabled = session.nightPremiumSnapshot ?? settings.first { $0.workplaceID == session.workplaceID }?.nightPremiumEnabled ?? true
                let result = try WorkPayCalculator.calculate(
                    session: session,
                    breaks: breaks.filter { $0.sessionID == session.id },
                    calendar: calendar, nightPremiumEnabled: nightEnabled,
                    overtimePremiumEnabled: session.overtimePremiumSnapshot ?? settings.first { $0.workplaceID == session.workplaceID }?.overtimePremiumEnabled ?? true,
                    holidayPaidMinutes: HolidayWorkMinutes.calculate(session: session,
                        breaks: breaks.filter { $0.sessionID == session.id }, holidayDates: holidayDates)
                )
                base += result.basePay
                premium += result.nightPremium
                overtimePremium += result.overtimePremium
                holidayPremium += result.holidayPremium
            } catch {
                skipped += 1
            }
        }
        var incentiveTotal: Decimal = 0
        for workplace in workplaces {
            let awards = WorkIncentiveCalculator.awards(
                sessions: sessions, rules: rules, workplace: workplace, calendar: calendar
            )
            for award in awards {
                guard let rule = rules.first(where: { $0.id == award.ruleID }) else { continue }
                var workplaceCalendar = calendar
                workplaceCalendar.firstWeekday = workplace.weekStartWeekday
                let unit: Calendar.Component = rule.period == .weekly ? .weekOfYear :
                    rule.period == .monthly ? .month : .day
                guard let awardInterval = workplaceCalendar.dateInterval(of: unit, for: award.periodStart) else { continue }
                let attributed = rule.period == .weekly
                    ? awardInterval.end.addingTimeInterval(-1) : award.periodStart
                if interval.contains(attributed) { incentiveTotal += award.amount }
            }
        }
        let manualTotal = manual.filter { interval.contains($0.earnedOn) }.reduce(Decimal.zero) {
            value, item in value + item.amount
        }
        let unique = Set(included.map { calendar.startOfDay(for: $0.startAt) })
        return MonthlyPaySummary(completedDays: unique.count, basePay: base,
                                 nightPremium: premium, overtimePremium: overtimePremium,
                                 holidayPremium: holidayPremium, automaticIncentives: incentiveTotal,
                                 manualIncentives: manualTotal, skippedSessions: skipped)
    }

    /// Returns *potential* next thresholds, not guaranteed payouts or admission.
    static func opportunities(
        on date: Date, sessions: [WorkSession], workplaces: [Workplace],
        rules: [IncentiveRule], calendar: Calendar
    ) -> [NextWorkdayOpportunity] {
        workplaces.flatMap { workplace -> [NextWorkdayOpportunity] in
            var cal = calendar
            cal.firstWeekday = workplace.weekStartWeekday
            let attendance = WorkAttendance.uniqueDays(of: sessions, workplaceID: workplace.id, calendar: cal)
            return rules.filter { $0.workplaceID == workplace.id && $0.isEnabled && $0.requiredAttendanceDays > 0 }
                .compactMap { rule -> NextWorkdayOpportunity? in
                    let component: Calendar.Component = rule.period == .weekly ? .weekOfYear :
                        rule.period == .monthly ? .month : .day
                    guard let interval = cal.dateInterval(of: component, for: date) else { return nil }
                    let count = attendance.filter { interval.contains($0) }.count
                    let remaining = max(0, rule.requiredAttendanceDays - count)
                    guard remaining > 0 else { return nil }
                    return NextWorkdayOpportunity(id: rule.id, workplaceName: workplace.name,
                        ruleName: rule.name, remainingDays: remaining, amount: rule.amount,
                        periodEnd: interval.end)
                }
        }.sorted { lhs, rhs in
            lhs.remainingDays == rhs.remainingDays ? lhs.amount > rhs.amount : lhs.remainingDays < rhs.remainingDays
        }
    }
}

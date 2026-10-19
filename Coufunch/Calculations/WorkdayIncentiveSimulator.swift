import Foundation

struct WorkdaySimulationResult {
    let workplaceID: UUID
    let candidateDate: Date
    let alreadyCompletedOnDate: Bool
    let newlyUnlockedBonus: Decimal
    let baselineBonus: Decimal
    let simulatedBonus: Decimal
    let triggeredRules: [String]
}

/// Non-persistent what-if forecast for exactly one additional completed attendance date.
/// Reuses the exact rule engine used by the actual pay dashboard.
enum WorkdayIncentiveSimulator {
    static func simulate(
        candidateDate: Date,
        workplace: Workplace,
        sessions: [WorkSession],
        rules: [IncentiveRule],
        calendar: Calendar
    ) -> WorkdaySimulationResult {
        let day = calendar.startOfDay(for: candidateDate)
        let attendance = WorkAttendance.uniqueDays(
            of: sessions, workplaceID: workplace.id, calendar: calendar
        )
        let existing = WorkIncentiveCalculator.awards(
            sessions: sessions, rules: rules, workplace: workplace, calendar: calendar
        )
        let alreadyCompleted = attendance.contains(day)
        guard !alreadyCompleted else {
            return WorkdaySimulationResult(workplaceID: workplace.id, candidateDate: day,
                alreadyCompletedOnDate: true, newlyUnlockedBonus: 0,
                baselineBonus: existing.reduce(Decimal.zero) { $0 + $1.amount },
                simulatedBonus: existing.reduce(Decimal.zero) { $0 + $1.amount },
                triggeredRules: [])
        }

        let hypothetical = WorkSession(
            workplaceID: workplace.id, startAt: day,
            status: .completed
        )
        let updated = WorkIncentiveCalculator.awards(
            sessions: sessions + [hypothetical], rules: rules,
            workplace: workplace, calendar: calendar
        )
        let oldTotal = existing.reduce(Decimal.zero) { $0 + $1.amount }
        let newTotal = updated.reduce(Decimal.zero) { $0 + $1.amount }

        // Compare award identity by rule and period, rather than only comparing
        // totals. This handles stackable + exclusive rules consistently.
        let previous = Set(existing.map { "\($0.ruleID.uuidString):\($0.periodStart.timeIntervalSince1970)" })
        let names = updated.filter {
            !previous.contains("\($0.ruleID.uuidString):\($0.periodStart.timeIntervalSince1970)")
        }.compactMap { award in
            rules.first(where: { $0.id == award.ruleID })?.name
        }

        return WorkdaySimulationResult(
            workplaceID: workplace.id, candidateDate: day,
            alreadyCompletedOnDate: false, newlyUnlockedBonus: newTotal - oldTotal,
            baselineBonus: oldTotal, simulatedBonus: newTotal,
            triggeredRules: names.sorted()
        )
    }
}

import Foundation

struct WeeklyAllowanceTimelineEntry: Identifiable {
    let id: String
    let workplaceName: String
    let amount: Decimal
    let earnedAt: Date
    let expectedPaymentAt: Date?
    let actualDepositAt: Date?
    let inclusion: BonusInclusion
}

/// Read-only payment timeline. Earned dates and bank deposit dates are separate.
/// An expected payday is shown only when verified holiday-year data is loaded.
enum WeeklyAllowanceTimeline {
    static func entries(
        sessions: [WorkSession],
        workplaces: [Workplace],
        rules: [IncentiveRule],
        receipts: [ReceivedPayRecord],
        holidays: Set<String>,
        loadedYears: Set<Int>,
        calendar baseCalendar: Calendar
    ) -> [WeeklyAllowanceTimelineEntry] {
        var result: [WeeklyAllowanceTimelineEntry] = []
        for workplace in workplaces {
            var calendar = baseCalendar
            calendar.firstWeekday = workplace.weekStartWeekday
            let awards = WorkIncentiveCalculator.awards(
                sessions: sessions, rules: rules, workplace: workplace, calendar: calendar)
            for award in awards {
                guard let rule = rules.first(where: { $0.id == award.ruleID }),
                      rule.period == .weekly,
                      let week = calendar.dateInterval(of: .weekOfYear, for: award.periodStart) else {
                    continue
                }
                let earnedAt = week.end.addingTimeInterval(-1)
                let lastShift = sessions.filter {
                    $0.workplaceID == workplace.id && $0.status == .completed &&
                    week.contains($0.startAt)
                }.max(by: { $0.startAt < $1.startAt })
                let receipt = lastShift.flatMap { shift in
                    receipts.filter { $0.sessionID == shift.id && $0.basis == .net }
                        .max(by: { $0.createdAt < $1.createdAt })
                }
                // The employer's bonus payment policy is not yet configured.
                // Do not infer a bonus payday from the final shift's daily payday.
                let expected: Date? = nil
                result.append(WeeklyAllowanceTimelineEntry(
                    id: "\(workplace.id.uuidString)-\(award.ruleID.uuidString)-\(award.periodStart.timeIntervalSince1970)",
                    workplaceName: workplace.name,
                    amount: award.amount,
                    earnedAt: earnedAt,
                    expectedPaymentAt: expected,
                    actualDepositAt: receipt?.bonusInclusion == .included ? receipt?.depositedAt : nil,
                    inclusion: receipt?.bonusInclusion ?? .unknown
                ))
            }
        }
        return result.sorted { $0.earnedAt > $1.earnedAt }
    }
}

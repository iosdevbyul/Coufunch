import Foundation

struct PayrollAuditEntry: Identifiable {
    let id: UUID
    let workplaceName: String
    let start: Date
    let end: Date
    let paidMinutes: Int
    let nightMinutes: Int
    let dailyOvertimeMinutes: Int
    let basePay: Decimal
    let nightPremium: Decimal
    let overtimePremium: Decimal
    let grossTotal: Decimal
}

struct PayrollAuditReport {
    let entries: [PayrollAuditEntry]
    let excluded: Int
    var shiftGross: Decimal { entries.reduce(Decimal.zero) { $0 + $1.grossTotal } }
}

/// Read-only payroll audit. The same calculation path powers normal finance screens.
/// Incomplete sessions are reported explicitly rather than silently treated as zero.
enum PayrollAuditCalculator {
    static func report(
        month: Date,
        sessions: [WorkSession],
        breaks: [WorkBreak],
        workplaces: [Workplace],
        settings: [WorkplacePaySettings],
        calendar: Calendar
    ) -> PayrollAuditReport {
        guard let interval = calendar.dateInterval(of: .month, for: month) else {
            return PayrollAuditReport(entries: [], excluded: 0)
        }
        let completed = sessions.filter {
            $0.status == .completed && interval.contains($0.startAt)
        }.sorted { $0.startAt < $1.startAt }
        var entries: [PayrollAuditEntry] = []
        var excluded = 0
        for session in completed {
            guard let end = session.endAt else {
                excluded += 1
                continue
            }
            let preferences = settings.first { $0.workplaceID == session.workplaceID }
            do {
                let pay = try WorkPayCalculator.calculate(
                    session: session,
                    breaks: breaks.filter { $0.sessionID == session.id },
                    calendar: calendar,
                    nightPremiumEnabled: session.nightPremiumSnapshot ?? preferences?.nightPremiumEnabled ?? true,
                    overtimePremiumEnabled: session.overtimePremiumSnapshot ?? preferences?.overtimePremiumEnabled ?? true
                )
                entries.append(PayrollAuditEntry(
                    id: session.id,
                    workplaceName: workplaces.first(where: { $0.id == session.workplaceID })?.name ?? "Unknown workplace",
                    start: session.startAt, end: end,
                    paidMinutes: pay.workedMinutes, nightMinutes: pay.nightMinutes,
                    dailyOvertimeMinutes: pay.overtimeMinutes, basePay: pay.basePay,
                    nightPremium: pay.nightPremium, overtimePremium: pay.overtimePremium,
                    grossTotal: pay.total
                ))
            } catch {
                excluded += 1
            }
        }
        return PayrollAuditReport(entries: entries, excluded: excluded)
    }
}

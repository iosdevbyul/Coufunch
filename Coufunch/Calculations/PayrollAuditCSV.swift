import Foundation

/// User-initiated plain-text export for comparison with a gross payslip.
/// No server upload is performed. Amounts are estimated KRW before deductions.
enum PayrollAuditCSV {
    static func make(report: PayrollAuditReport, calendar: Calendar) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = calendar.timeZone

        let header = [
            "Workplace", "Start", "End", "Paid minutes",
            "Night minutes", "Daily overtime minutes",
            "Base KRW", "Night premium KRW", "Overtime premium KRW", "Holiday premium KRW", "Gross KRW"
        ].joined(separator: ",")

        let rows = report.entries.map { entry in
            [
                escaped(entry.workplaceName),
                escaped(formatter.string(from: entry.start)),
                escaped(formatter.string(from: entry.end)),
                String(entry.paidMinutes),
                String(entry.nightMinutes),
                String(entry.dailyOvertimeMinutes),
                number(entry.basePay),
                number(entry.nightPremium),
                number(entry.overtimePremium),
                number(entry.holidayPremium),
                number(entry.grossTotal)
            ].joined(separator: ",")
        }

        return ([header] + rows).joined(separator: "\n") + "\n"
    }

    private static func number(_ amount: Decimal) -> String {
        NSDecimalNumber(decimal: amount).stringValue
    }

    private static func escaped(_ value: String) -> String {
        // Prevent spreadsheet formula execution when exported text is pasted into a sheet.
        let safe = value.first.map { "=+-@".contains($0) } == true ? "'" + value : value
        return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

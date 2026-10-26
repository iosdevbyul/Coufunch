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

    /// Readable Korean export for a real .csv attachment. All monetary cells are
    /// integers, with no currency symbols, so Numbers and Excel can total them.
    static func readable(
        report: PayrollAuditReport,
        calendar: Calendar,
        incentives: [(date: Date, name: String, amount: Decimal)]
    ) -> String {
        let date = DateFormatter()
        date.calendar = calendar
        date.timeZone = calendar.timeZone
        date.locale = Locale(identifier: "ko_KR")
        date.dateFormat = "yyyy-MM-dd"
        let time = DateFormatter()
        time.calendar = calendar
        time.timeZone = calendar.timeZone
        time.locale = Locale(identifier: "ko_KR")
        time.dateFormat = "HH:mm"

        let header = [
            "날짜", "구분", "근무지/수당", "시작", "종료", "유급시간(분)",
            "야간(분)", "연장(분)", "기본급(원)", "야간수당(원)",
            "연장수당(원)", "휴일수당(원)", "인센티브(원)", "세전합계(원)"
        ].joined(separator: ",")

        let shiftRows: [(Date, String)] = report.entries.map { entry in
            let values = [
                escaped(date.string(from: entry.start)), "근무", escaped(entry.workplaceName),
                escaped(time.string(from: entry.start)), escaped(time.string(from: entry.end)),
                String(entry.paidMinutes), String(entry.nightMinutes),
                String(entry.dailyOvertimeMinutes), number(entry.basePay),
                number(entry.nightPremium), number(entry.overtimePremium),
                number(entry.holidayPremium), "0", number(entry.grossTotal)
            ]
            return (entry.start, values.joined(separator: ","))
        }
        let bonusRows: [(Date, String)] = incentives.map { item in
            let values = [
                escaped(date.string(from: item.date)), "인센티브", escaped(item.name),
                "", "", "", "", "", "", "", "", "",
                number(item.amount), number(item.amount)
            ]
            return (item.date, values.joined(separator: ","))
        }
        let lines = (shiftRows + bonusRows).sorted { $0.0 < $1.0 }.map(\.1)
        let gross = report.shiftGross + incentives.reduce(Decimal.zero) { $0 + $1.amount }
        let summary = ["", "합계", "", "", "", "", "", "", "", "", "", "", "",
                       number(gross)].joined(separator: ",")
        return ([header] + lines + [summary]).joined(separator: "\n") + "\n"
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

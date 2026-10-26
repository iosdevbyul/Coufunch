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
        incentives: [(date: Date, name: String, amount: Decimal)],
        actualNetBySession: [UUID: Decimal] = [:],
        totalNet: Decimal? = nil,
        locale: Locale = .current
    ) -> String {
        let date = DateFormatter()
        date.calendar = calendar
        date.timeZone = calendar.timeZone
        date.locale = locale
        date.dateFormat = "yyyy-MM-dd"
        let time = DateFormatter()
        time.calendar = calendar
        time.timeZone = calendar.timeZone
        time.locale = locale
        time.dateFormat = "HH:mm"

        let isKorean = locale.language.languageCode?.identifier == "ko"
        func localized(_ korean: String, _ english: String) -> String { isKorean ? korean : english }
        let header = [
            localized("날짜", "Date"), localized("구분", "Type"), localized("근무지/수당", "Workplace / Bonus"), localized("시작", "Start"), localized("종료", "End"), localized("유급시간(분)", "Paid Minutes"),
            localized("야간(분)", "Night Minutes"), localized("연장(분)", "Overtime Minutes"), localized("기본급(원)", "Base Pay (KRW)"), localized("야간수당(원)", "Night Premium (KRW)"),
            localized("연장수당(원)", "Overtime Premium (KRW)"), localized("휴일수당(원)", "Holiday Premium (KRW)"), localized("인센티브(원)", "Incentive (KRW)"), localized("세전합계(원)", "Gross Total (KRW)"), localized("세후금액(원)", "Net Pay (KRW)"), localized("세후구분", "Net Pay Source")
        ].joined(separator: ",")

        let shiftRows: [(Date, String)] = report.entries.map { entry in
            let actual = actualNetBySession[entry.id]
            let net = actual ?? EstimatedTakeHomeCalculator.calculate(gross: entry.grossTotal, shifts: []).net
            let values = [
                escaped(date.string(from: entry.start)), localized("근무", "Shift"), escaped(entry.workplaceName),
                escaped(time.string(from: entry.start)), escaped(time.string(from: entry.end)),
                String(entry.paidMinutes), String(entry.nightMinutes),
                String(entry.dailyOvertimeMinutes), number(entry.basePay),
                number(entry.nightPremium), number(entry.overtimePremium),
                number(entry.holidayPremium), "0", number(entry.grossTotal),
                number(net), actual == nil ? localized("예상", "Estimated") : localized("실제", "Actual")
            ]
            return (entry.start, values.joined(separator: ","))
        }
        let bonusRows: [(Date, String)] = incentives.map { item in
            let values = [
                escaped(date.string(from: item.date)), localized("인센티브", "Incentive"), escaped(item.name),
                "", "", "", "", "", "", "", "", "",
                number(item.amount), number(item.amount),
                number(EstimatedTakeHomeCalculator.calculate(gross: item.amount, shifts: []).net), localized("예상(수당)", "Estimated (bonus)")
            ]
            return (item.date, values.joined(separator: ","))
        }
        let lines = (shiftRows + bonusRows).sorted { $0.0 < $1.0 }.map { $0.1 }
        let gross = report.shiftGross + incentives.reduce(Decimal.zero) { $0 + $1.amount }
        let estimatedNet = EstimatedTakeHomeCalculator.calculate(gross: gross, shifts: []).net
        let summary = ["", localized("합계", "Total"), "", "", "", "", "", "", "", "", "", "", "",
                       number(gross), number(totalNet ?? estimatedNet),
                       totalNet == nil ? localized("예상", "Estimated") : localized("실제입력 반영", "Actual entries applied")].joined(separator: ",")
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

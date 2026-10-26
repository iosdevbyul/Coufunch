import XCTest
@testable import Coufunch

@MainActor
final class PayrollAuditCSVTests: XCTestCase {
    func testExportsNumbersAndQuotesWorkplaceNamesSafely() {
        let start = Date(timeIntervalSince1970: 1_792_000_000)
        let entry = PayrollAuditEntry(
            id: UUID(), workplaceName: "=SUM(1,2) \"Branch\"",
            start: start, end: start.addingTimeInterval(3600),
            paidMinutes: 60, nightMinutes: 0, dailyOvertimeMinutes: 0,
            basePay: 10_320, nightPremium: 0, overtimePremium: 0, holidayPremium: 0,
            grossTotal: 10_320
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let csv = PayrollAuditCSV.make(
            report: PayrollAuditReport(entries: [entry], excluded: 0),
            calendar: calendar
        )
        XCTAssertTrue(csv.contains("\"'=SUM(1,2) \"\"Branch\"\"\""))
        XCTAssertTrue(csv.contains(",60,0,0,10320,0,0,0,10320"))
        XCTAssertEqual(csv.split(separator: "\n").count, 2)
    }

    func testReadableExportUsesActualNetWhenAvailableAndEstimatedOtherwise() {
        let start = Date(timeIntervalSince1970: 1_792_000_000)
        let first = PayrollAuditEntry(
            id: UUID(), workplaceName: "센터",
            start: start, end: start.addingTimeInterval(3600),
            paidMinutes: 60, nightMinutes: 0, dailyOvertimeMinutes: 0,
            basePay: 100_000, nightPremium: 0, overtimePremium: 0,
            holidayPremium: 0, grossTotal: 100_000
        )
        let second = PayrollAuditEntry(
            id: UUID(), workplaceName: "센터",
            start: start.addingTimeInterval(86_400),
            end: start.addingTimeInterval(90_000),
            paidMinutes: 60, nightMinutes: 0, dailyOvertimeMinutes: 0,
            basePay: 100_000, nightPremium: 0, overtimePremium: 0,
            holidayPremium: 0, grossTotal: 100_000
        )
        let csv = PayrollAuditCSV.readable(
            report: PayrollAuditReport(entries: [first, second], excluded: 0),
            calendar: .current,
            incentives: [],
            actualNetBySession: [first.id: 93_000],
            totalNet: 183_000,
            locale: Locale(identifier: "ko_KR")
        )
        XCTAssertTrue(csv.contains("세후금액(원),세후구분"))
        XCTAssertTrue(csv.contains("100000,93000,실제"))
        XCTAssertTrue(csv.contains("100000,") && csv.contains(",예상"))
        XCTAssertTrue(csv.contains("200000,183000,실제입력 반영"))
    }

    func testEnglishExportHeadersAndNetLabels() {
        let start = Date(timeIntervalSince1970: 1_792_000_000)
        let entry = PayrollAuditEntry(
            id: UUID(), workplaceName: "Center",
            start: start, end: start.addingTimeInterval(3600),
            paidMinutes: 60, nightMinutes: 0, dailyOvertimeMinutes: 0,
            basePay: 100_000, nightPremium: 0, overtimePremium: 0,
            holidayPremium: 0, grossTotal: 100_000
        )
        let csv = PayrollAuditCSV.readable(
            report: PayrollAuditReport(entries: [entry], excluded: 0),
            calendar: .current,
            incentives: [],
            actualNetBySession: [entry.id: 93_000],
            totalNet: 93_000,
            locale: Locale(identifier: "en_US")
        )
        XCTAssertTrue(csv.contains("Date,Type,Workplace / Bonus"))
        XCTAssertTrue(csv.contains("Net Pay (KRW),Net Pay Source"))
        XCTAssertTrue(csv.contains("100000,93000,Actual"))
        XCTAssertFalse(csv.contains("세후"))
    }

    func testEmptyReportHasHeaderWithoutSyntheticRecords() {
        let csv = PayrollAuditCSV.make(
            report: PayrollAuditReport(entries: [], excluded: 2),
            calendar: .current
        )
        XCTAssertEqual(csv.split(separator: "\n").count, 1)
        XCTAssertTrue(csv.contains("Gross KRW"))
    }
}

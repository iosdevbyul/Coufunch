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
        XCTAssertTrue(csv.contains(",60,0,0,10320,0,0,10320"))
        XCTAssertEqual(csv.split(separator: "\n").count, 2)
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

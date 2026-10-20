import XCTest
import SwiftData
@testable import Coufunch

@MainActor
final class PayrollAuditPersistenceTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return value
    }

    private func date(_ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    func testAuditMatchesSameCalculatorAsMonthlySummary() {
        let workplace = Workplace(name: "Example")
        let session = WorkSession(workplaceID: workplace.id, startAt: date(19, 19),
                                  endAt: date(20, 6), status: .completed,
                                  hourlyRateSnapshot: 10_320,
                                  nightPremiumSnapshot: true,
                                  overtimePremiumSnapshot: true)
        let rest = WorkBreak(sessionID: session.id, startAt: date(19, 22), endAt: date(19, 23))
        let audit = PayrollAuditCalculator.report(month: date(19, 0),
            sessions: [session], breaks: [rest], workplaces: [workplace],
            settings: [], calendar: calendar)
        let summary = WorkFinanceSummary.summarize(month: date(19, 0),
            sessions: [session], breaks: [rest], workplaces: [workplace],
            settings: [], rules: [], manual: [], calendar: calendar)
        XCTAssertEqual(audit.entries.count, 1)
        XCTAssertEqual(audit.entries[0].grossTotal, summary.total)
        XCTAssertEqual(audit.entries[0].dailyOvertimeMinutes, 120)
        XCTAssertEqual(audit.entries[0].nightMinutes, 420)
    }

    func testAuditSkipsBrokenRecordsWithoutInventingPay() {
        let workplace = Workplace(name: "Example")
        let incomplete = WorkSession(workplaceID: workplace.id,
                                     startAt: date(19, 8), status: .completed)
        let audit = PayrollAuditCalculator.report(month: date(19, 0),
            sessions: [incomplete], breaks: [], workplaces: [workplace],
            settings: [], calendar: calendar)
        XCTAssertTrue(audit.entries.isEmpty)
        XCTAssertEqual(audit.excluded, 1)
    }

    func testOnDiskStoreReopensWithOriginalPaySnapshotsAndBreaks() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
            "CoufunchAudit-\(UUID().uuidString)", isDirectory: true
        )
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let storeURL = folder.appendingPathComponent("PayStore.sqlite")
        let schema = Schema([Workplace.self, WorkplacePaySettings.self,
                             WorkSession.self, WorkBreak.self])
        let workplaceID = UUID()
        let sessionID = UUID()

        do {
            let configuration = ModelConfiguration(schema: schema, url: storeURL)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = container.mainContext
            context.insert(Workplace(id: workplaceID, name: "Example"))
            context.insert(WorkplacePaySettings(workplaceID: workplaceID,
                payMode: .customHourly, customHourlyRate: 20_000,
                nightPremiumEnabled: false, overtimePremiumEnabled: false))
            context.insert(WorkSession(id: sessionID, workplaceID: workplaceID,
                startAt: date(19, 8), endAt: date(19, 18),
                status: .completed, payMode: .customHourly,
                hourlyRateSnapshot: 12_000,
                nightPremiumSnapshot: true, overtimePremiumSnapshot: true))
            context.insert(WorkBreak(sessionID: sessionID,
                startAt: date(19, 12), endAt: date(19, 13)))
            try context.save()
        }

        do {
            let configuration = ModelConfiguration(schema: schema, url: storeURL)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = container.mainContext
            let sessions = try context.fetch(FetchDescriptor<WorkSession>())
            let breaks = try context.fetch(FetchDescriptor<WorkBreak>())
            XCTAssertEqual(sessions.count, 1)
            XCTAssertEqual(breaks.count, 1)
            XCTAssertEqual(sessions[0].id, sessionID)
            XCTAssertEqual(sessions[0].hourlyRateSnapshot, 12_000)
            XCTAssertEqual(sessions[0].nightPremiumSnapshot, true)
            XCTAssertEqual(sessions[0].overtimePremiumSnapshot, true)
            XCTAssertEqual(breaks[0].sessionID, sessionID)
        }
    }
}

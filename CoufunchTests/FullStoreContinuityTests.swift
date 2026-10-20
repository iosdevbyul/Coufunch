import XCTest
import SwiftData
@testable import Coufunch

@MainActor
final class FullStoreContinuityTests: XCTestCase {
    func testReopenStorePreservesAllFinancialEntitiesAndLinks() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CoufunchFullStore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let schema = Schema([
            Workplace.self, WorkplacePaySettings.self, WorkSession.self,
            WorkBreak.self, IncentiveRule.self, ManualIncentive.self,
            ReceivedPayRecord.self
        ])
        let store = directory.appendingPathComponent("Coufunch.sqlite")
        let workplaceID = UUID(), sessionID = UUID(), ruleID = UUID(), receiptID = UUID()
        let start = Date(timeIntervalSince1970: 1_792_387_200)
        let end = start.addingTimeInterval(9 * 3600)
        let month = Calendar.current.dateInterval(of: .month, for: start)!.start

        do {
            let config = ModelConfiguration(schema: schema, url: store)
            let container = try ModelContainer(for: schema, configurations: [config])
            let context = container.mainContext
            context.insert(Workplace(id: workplaceID, name: "Saved Workplace"))
            context.insert(WorkplacePaySettings(workplaceID: workplaceID,
                payMode: .minimumHourly, nightPremiumEnabled: true,
                overtimePremiumEnabled: true))
            context.insert(WorkSession(id: sessionID, workplaceID: workplaceID,
                startAt: start, endAt: end, status: .completed,
                payMode: .minimumHourly, hourlyRateSnapshot: 10_320,
                nightPremiumSnapshot: true, overtimePremiumSnapshot: true))
            context.insert(WorkBreak(sessionID: sessionID, startAt: start.addingTimeInterval(4 * 3600),
                endAt: start.addingTimeInterval(5 * 3600)))
            context.insert(IncentiveRule(id: ruleID, workplaceID: workplaceID,
                name: "Bonus", period: .weekly, requiredAttendanceDays: 5, amount: 80_000))
            context.insert(ManualIncentive(workplaceID: workplaceID, sessionID: sessionID,
                earnedOn: start, name: "Adjustment", amount: 20_000))
            context.insert(ReceivedPayRecord(id: receiptID, monthStart: month,
                workplaceID: workplaceID, amount: 110_000, basis: .net, note: "Bank deposit"))
            try context.save()
        }

        do {
            let config = ModelConfiguration(schema: schema, url: store)
            let container = try ModelContainer(for: schema, configurations: [config])
            let context = container.mainContext
            let workplace = try XCTUnwrap(context.fetch(FetchDescriptor<Workplace>()).first)
            let setting = try XCTUnwrap(context.fetch(FetchDescriptor<WorkplacePaySettings>()).first)
            let session = try XCTUnwrap(context.fetch(FetchDescriptor<WorkSession>()).first)
            let rest = try XCTUnwrap(context.fetch(FetchDescriptor<WorkBreak>()).first)
            let rule = try XCTUnwrap(context.fetch(FetchDescriptor<IncentiveRule>()).first)
            let bonus = try XCTUnwrap(context.fetch(FetchDescriptor<ManualIncentive>()).first)
            let receipt = try XCTUnwrap(context.fetch(FetchDescriptor<ReceivedPayRecord>()).first)

            XCTAssertEqual(workplace.id, workplaceID)
            XCTAssertEqual(workplace.name, "Saved Workplace")
            XCTAssertEqual(setting.workplaceID, workplaceID)
            XCTAssertEqual(setting.payMode, .minimumHourly)
            XCTAssertEqual(session.id, sessionID)
            XCTAssertEqual(session.hourlyRateSnapshot, 10_320)
            XCTAssertEqual(session.overtimePremiumSnapshot, true)
            XCTAssertEqual(rest.sessionID, sessionID)
            XCTAssertEqual(rule.id, ruleID)
            XCTAssertEqual(rule.amount, 80_000)
            XCTAssertEqual(bonus.sessionID, sessionID)
            XCTAssertEqual(bonus.amount, 20_000)
            XCTAssertEqual(receipt.id, receiptID)
            XCTAssertEqual(receipt.basis, .net)
            XCTAssertEqual(receipt.note, "Bank deposit")
        }
    }
}

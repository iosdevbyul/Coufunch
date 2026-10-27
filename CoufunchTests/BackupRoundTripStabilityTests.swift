import Foundation
import SwiftData
import XCTest
@testable import Coufunch

@MainActor
final class BackupRoundTripStabilityTests: XCTestCase {
    private func container() throws -> ModelContainer {
        let schema = Schema([
            Workplace.self, WorkplacePaySettings.self, WorkSession.self,
            WorkBreak.self, IncentiveRule.self, ManualIncentive.self,
            ReceivedPayRecord.self
        ])
        return try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        ])
    }

    func testSevenEntityRoundTripAndIdempotentImport() throws {
        let source = try container()
        let a = source.mainContext
        let workplace = Workplace(name: "Test workplace")
        let shiftStart = Date(timeIntervalSince1970: 1_793_000_000)
        let shiftEnd = shiftStart.addingTimeInterval(9 * 3600)
        let shift = WorkSession(
            workplaceID: workplace.id, startAt: shiftStart, endAt: shiftEnd,
            status: .completed, payMode: .fixedDaily,
            fixedDailyPaySnapshot: 108_000, nightPremiumSnapshot: false
        )
        let rest = WorkBreak(
            sessionID: shift.id,
            startAt: shiftStart.addingTimeInterval(4 * 3600),
            endAt: shiftStart.addingTimeInterval(5 * 3600)
        )
        let paySetting = WorkplacePaySettings(
            workplaceID: workplace.id, payMode: .fixedDaily,
            fixedDailyPay: 108_000, nightPremiumEnabled: false
        )
        let rule = IncentiveRule(
            workplaceID: workplace.id, name: "Weekly",
            period: .weekly, requiredAttendanceDays: 5, amount: 80_000
        )
        let incentive = ManualIncentive(
            workplaceID: workplace.id, sessionID: shift.id, earnedOn: shiftStart,
            name: "Manual", amount: 12_000
        )
        let receipt = ReceivedPayRecord(
            monthStart: shiftStart, workplaceID: workplace.id,
            amount: 97_000, basis: .net, note: "Actual",
            sessionID: shift.id, depositedAt: shiftEnd
        )
        for object in [workplace as any PersistentModel, shift, rest, paySetting,
                       rule, incentive, receipt] {
            a.insert(object)
        }
        try a.save()

        let archive = try CoufunchBackupStore.decode(
            CoufunchBackupStore.encode(CoufunchBackupStore.create(from: a))
        )
        XCTAssertEqual(archive.recordCount, 7)

        let destination = try container()
        let b = destination.mainContext
        XCTAssertEqual(try CoufunchBackupStore.restore(archive, into: b), 7)
        XCTAssertEqual(try CoufunchBackupStore.restore(archive, into: b), 0)

        let restoredShift = try XCTUnwrap(b.fetch(FetchDescriptor<WorkSession>()).first)
        XCTAssertEqual(restoredShift.id, shift.id)
        XCTAssertEqual(restoredShift.workplaceID, workplace.id)
        XCTAssertEqual(restoredShift.startAt, shiftStart)
        XCTAssertEqual(restoredShift.endAt, shiftEnd)
        XCTAssertEqual(restoredShift.fixedDailyPaySnapshot, 108_000)
        XCTAssertEqual(try b.fetch(FetchDescriptor<Workplace>()).count, 1)
        XCTAssertEqual(try b.fetch(FetchDescriptor<WorkplacePaySettings>()).count, 1)
        XCTAssertEqual(try b.fetch(FetchDescriptor<WorkBreak>()).first?.sessionID, shift.id)
        XCTAssertEqual(try b.fetch(FetchDescriptor<IncentiveRule>()).first?.amount, 80_000)
        XCTAssertEqual(try b.fetch(FetchDescriptor<ManualIncentive>()).first?.sessionID, shift.id)
        XCTAssertEqual(try b.fetch(FetchDescriptor<ReceivedPayRecord>()).first?.amount, 97_000)
    }

    func testInvalidReferenceDoesNotInsertAnyRecords() throws {
        let source = try container()
        let workplace = Workplace(name: "Valid")
        source.mainContext.insert(workplace)
        try source.mainContext.save()
        let original = try CoufunchBackupStore.create(from: source.mainContext)
        let payload = try CoufunchBackupStore.encode(original)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        json["breaks"] = [[
            "id": UUID().uuidString,
            "sessionID": UUID().uuidString,
            "startAt": "1793000000",
            "endAt": "1793000300"
        ]]
        let archive = try CoufunchBackupStore.decode(
            JSONSerialization.data(withJSONObject: json)
        )
        let destination = try container()
        XCTAssertThrowsError(try CoufunchBackupStore.restore(archive, into: destination.mainContext))
        XCTAssertEqual(try destination.mainContext.fetch(FetchDescriptor<Workplace>()).count, 0)
    }
}

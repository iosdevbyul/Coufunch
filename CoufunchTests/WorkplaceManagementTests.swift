import XCTest
import SwiftData
@testable import Coufunch

@MainActor
final class WorkplaceManagementTests: XCTestCase {
    func testUpdatingWorkplaceDefaultsDoesNotChangeRecordedPaySnapshots() throws {
        let schema = Schema([
            Workplace.self, WorkplacePaySettings.self,
            WorkSession.self, IncentiveRule.self, ManualIncentive.self
        ])
        let container = try ModelContainer(
            for: schema, configurations: [
                ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            ]
        )
        let context = container.mainContext
        let workplace = Workplace(name: "First name")
        let preferences = WorkplacePaySettings(
            workplaceID: workplace.id, payMode: .customHourly,
            customHourlyRate: 12_000, nightPremiumEnabled: true,
            overtimePremiumEnabled: true
        )
        let shift = WorkSession(
            workplaceID: workplace.id, startAt: .now,
            hourlyRateSnapshot: 12_000, nightPremiumSnapshot: true,
            overtimePremiumSnapshot: true
        )
        context.insert(workplace)
        context.insert(preferences)
        context.insert(shift)
        try context.save()

        workplace.name = "Updated name"
        preferences.customHourlyRate = 15_000
        preferences.nightPremiumEnabled = false
        preferences.overtimePremiumEnabled = false
        try context.save()

        let sessions = try context.fetch(FetchDescriptor<WorkSession>())
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].hourlyRateSnapshot, 12_000)
        XCTAssertEqual(sessions[0].nightPremiumSnapshot, true)
        XCTAssertEqual(sessions[0].overtimePremiumSnapshot, true)
        XCTAssertEqual(workplace.name, "Updated name")
    }

    func testEditingManualIncentiveDoesNotCreateDuplicate() throws {
        let schema = Schema([ManualIncentive.self])
        let container = try ModelContainer(
            for: schema, configurations: [
                ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            ]
        )
        let context = container.mainContext
        let workplaceID = UUID()
        let award = ManualIncentive(
            workplaceID: workplaceID, earnedOn: .now,
            name: "Adjustment", amount: 20_000
        )
        context.insert(award)
        try context.save()
        award.amount = 25_000
        try context.save()
        let saved = try context.fetch(FetchDescriptor<ManualIncentive>())
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved[0].amount, 25_000)
    }
}

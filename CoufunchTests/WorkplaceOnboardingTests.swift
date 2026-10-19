import XCTest
import SwiftData
@testable import Coufunch

@MainActor
final class WorkplaceOnboardingTests: XCTestCase {
    func testExampleIncentivesMatchOptInValuesAndStack() {
        let workplaceID = UUID()
        let rules = IncentivePreset.exampleRules(workplaceID: workplaceID)
        XCTAssertEqual(rules.count, 3)
        XCTAssertEqual(rules.filter { $0.period == .weekly }.count, 2)
        XCTAssertEqual(rules.first?.requiredAttendanceDays, 5)
        XCTAssertEqual(rules.first?.amount, 80_000)
        XCTAssertEqual(rules[1].requiredAttendanceDays, 6)
        XCTAssertEqual(rules[1].amount, 40_000)
        XCTAssertEqual(rules[2].requiredAttendanceDays, 15)
        XCTAssertEqual(rules[2].amount, 70_000)
        XCTAssertTrue(rules.allSatisfy { $0.workplaceID == workplaceID && $0.canStack })
    }

    func testWorkplaceAndPayDefaultsPersist() throws {
        let schema = Schema([Workplace.self, WorkplacePaySettings.self, IncentiveRule.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext
        let workplace = Workplace(name: "My workplace")
        let settings = WorkplacePaySettings(workplaceID: workplace.id, payMode: .fixedDaily, fixedDailyPay: 300_000)
        context.insert(workplace)
        context.insert(settings)
        try context.save()

        let workplaces = try context.fetch(FetchDescriptor<Workplace>())
        let savedSettings = try context.fetch(FetchDescriptor<WorkplacePaySettings>())
        XCTAssertEqual(workplaces.count, 1)
        XCTAssertEqual(savedSettings.count, 1)
        XCTAssertEqual(savedSettings[0].workplaceID, workplaces[0].id)
        XCTAssertEqual(savedSettings[0].payMode, .fixedDaily)
        XCTAssertEqual(savedSettings[0].fixedDailyPay, 300_000)
    }
}

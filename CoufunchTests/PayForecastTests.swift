import XCTest
import SwiftData
@testable import Coufunch

@MainActor
final class PayForecastTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return cal
    }
    private func date(_ day: Int, _ hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    func testStatusesRemainSeparated() {
        let workplaceID = UUID()
        let records = [
            WorkSession(workplaceID: workplaceID, startAt: date(19), endAt: date(19, 17),
                        status: .completed, payMode: .fixedDaily, fixedDailyPaySnapshot: 100_000),
            WorkSession(workplaceID: workplaceID, startAt: date(20), endAt: date(20, 17),
                        status: .confirmed, payMode: .fixedDaily, fixedDailyPaySnapshot: 80_000),
            WorkSession(workplaceID: workplaceID, startAt: date(21), endAt: date(21, 17),
                        status: .applied, payMode: .fixedDaily, fixedDailyPaySnapshot: 70_000)
        ]
        let result = PayForecastCalculator.calculate(month: date(1), sessions: records,
            breaks: [], settings: [], calendar: calendar)
        XCTAssertEqual(result.completedGross, 100_000)
        XCTAssertEqual(result.confirmedGross, 80_000)
        XCTAssertEqual(result.appliedGross, 70_000)
        XCTAssertEqual(result.securedGross, 180_000)
        XCTAssertEqual(result.possibleGross, 250_000)
        XCTAssertEqual(result.completedCount, 1)
        XCTAssertEqual(result.confirmedCount, 1)
        XCTAssertEqual(result.appliedCount, 1)
    }

    func testUnpricedSessionsAreFlaggedInsteadOfCountedAsZero() {
        let record = WorkSession(workplaceID: UUID(), startAt: date(19),
                                 status: .confirmed, payMode: .minimumHourly)
        let result = PayForecastCalculator.calculate(month: date(1),
            sessions: [record], breaks: [], settings: [], calendar: calendar)
        XCTAssertEqual(result.unpricedCount, 1)
        XCTAssertEqual(result.confirmedCount, 0)
    }

    func testReceivedPayBasisAndDataPersist() throws {
        let schema = Schema([ReceivedPayRecord.self])
        let container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        ])
        let receipt = ReceivedPayRecord(monthStart: date(1), amount: 340_000,
                                        basis: .net, note: "Deposited")
        container.mainContext.insert(receipt)
        try container.mainContext.save()
        let saved = try container.mainContext.fetch(FetchDescriptor<ReceivedPayRecord>())
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved[0].amount, 340_000)
        XCTAssertEqual(saved[0].basis, .net)
        XCTAssertEqual(saved[0].note, "Deposited")
    }
    func testManualScenarioDoesNotInventAdditionalWork() {
        XCTAssertEqual(ManualPayScenario.projectedGross(
            recordedGross: 350_000, shiftCount: 0, grossPerShift: 108_000
        ), 350_000)
        XCTAssertEqual(ManualPayScenario.projectedGross(
            recordedGross: 350_000, shiftCount: 3, grossPerShift: 108_000
        ), 674_000)
    }

    func testManualScenarioDoesNotSubtractRecordedEarnings() {
        XCTAssertEqual(ManualPayScenario.additionalGross(
            shiftCount: 0, grossPerShift: 108_000
        ), 0)
        XCTAssertEqual(ManualPayScenario.additionalGross(
            shiftCount: -1, grossPerShift: 108_000
        ), 0)
        XCTAssertEqual(ManualPayScenario.additionalGross(
            shiftCount: 4, grossPerShift: -10
        ), 0)
    }

}

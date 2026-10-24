import XCTest
import SwiftData
@testable import Coufunch

final class ActualPayReconciliationTests: XCTestCase {
    func testUnenteredShiftsKeepOriginalMonthlyEstimate() {
        let id = UUID()
        XCTAssertEqual(ActualPayReconciliation.total(
            estimatedMonthlyNet: 300_000,
            shiftGross: [(id: id, gross: 108_000)],
            actualBySession: [:]), 300_000)
    }

    func testActualDepositsReplaceOnlyMatchingShiftEstimates() {
        let ids = (0..<4).map { _ in UUID() }
        let gross = Decimal(108_000)
        let perShiftNet = EstimatedTakeHomeCalculator.calculate(
            gross: gross, shifts: []).net
        let baseline = perShiftNet * 4 + 70_000
        let actuals: [UUID: Decimal] = [
            ids[0]: 97_850, ids[1]: 97_820, ids[2]: 97_840
        ]
        let total = ActualPayReconciliation.total(
            estimatedMonthlyNet: baseline,
            shiftGross: ids.map { (id: $0, gross: gross) },
            actualBySession: actuals
        )
        XCTAssertEqual(total, Decimal(97_850 + 97_820 + 97_840) + perShiftNet + 70_000)
    }

    func testEditingAndRemovingAnActualDepositRestoresEstimate() {
        let id = UUID()
        let baseline: Decimal = 97_500
        let shifts: [(id: UUID, gross: Decimal)] = [(id: id, gross: 108_000)]
        let original = ActualPayReconciliation.total(
            estimatedMonthlyNet: baseline, shiftGross: shifts,
            actualBySession: [id: 97_850])
        let edited = ActualPayReconciliation.total(
            estimatedMonthlyNet: baseline, shiftGross: shifts,
            actualBySession: [id: 97_820])
        let cleared = ActualPayReconciliation.total(
            estimatedMonthlyNet: baseline, shiftGross: shifts,
            actualBySession: [:])
        XCTAssertEqual(edited - original, -30)
        XCTAssertEqual(cleared, baseline)
    }

    func testWeeklyBonusIncludedVsSeparate() {
        let id = UUID()
        let gross: Decimal = 108000
        let shiftNet = EstimatedTakeHomeCalculator.calculate(gross: gross, shifts: []).net
        let bonusNet = EstimatedTakeHomeCalculator.calculate(gross: 80000, shifts: []).net
        let base = shiftNet + bonusNet
        let shift = [(id: id, gross: gross)]
        let actual: [UUID: Decimal] = [id: 175000]
        let included = ActualPayReconciliation.total(
            estimatedMonthlyNet: base, shiftGross: shift,
            actualBySession: actual, bonusNetBySession: [id: bonusNet],
            bonusInclusionBySession: [id: .included])
        let excluded = ActualPayReconciliation.total(
            estimatedMonthlyNet: base, shiftGross: shift,
            actualBySession: actual, bonusNetBySession: [id: bonusNet],
            bonusInclusionBySession: [id: .excluded])
        XCTAssertEqual(included, 175000)
        XCTAssertEqual(excluded, 175000 + bonusNet)
    }

    func testUnknownSessionDoesNotChangeMonthlyTotal() {
        XCTAssertEqual(ActualPayReconciliation.total(
            estimatedMonthlyNet: 123_456, shiftGross: [],
            actualBySession: [UUID(): 97_850]), 123_456)
    }
}

@MainActor
final class ActualPayRecordContinuityTests: XCTestCase {
    func testLegacyAndSessionLinkedPaymentsSurviveStoreReopen() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CoufunchActualPay-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let schema = Schema([ReceivedPayRecord.self])
        let store = directory.appendingPathComponent("Payments.sqlite")
        let sessionID = UUID()
        let month = Date(timeIntervalSince1970: 1_780_000_000)

        do {
            let container = try ModelContainer(for: schema,
                configurations: [ModelConfiguration(schema: schema, url: store)])
            let context = container.mainContext
            context.insert(ReceivedPayRecord(monthStart: month,
                amount: 110_000, basis: .net, note: "Legacy bank deposit"))
            context.insert(ReceivedPayRecord(monthStart: month,
                amount: 97_850, basis: .net, sessionID: sessionID))
            try context.save()
        }
        do {
            let container = try ModelContainer(for: schema,
                configurations: [ModelConfiguration(schema: schema, url: store)])
            let records = try container.mainContext.fetch(FetchDescriptor<ReceivedPayRecord>())
            XCTAssertEqual(records.count, 2)
            XCTAssertEqual(records.first(where: { $0.sessionID == nil })?.note, "Legacy bank deposit")
            XCTAssertEqual(records.first(where: { $0.sessionID == sessionID })?.amount, 97_850)
        }
    }
}

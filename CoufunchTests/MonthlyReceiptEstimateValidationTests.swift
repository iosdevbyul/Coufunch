import XCTest
@testable import Coufunch

final class MonthlyReceiptEstimateValidationTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return value
    }

    private var month: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 1))!
    }

    private func receipt(
        workplace: UUID, amount: Decimal = 900_000,
        basis: ReceivedPayBasis = .net,
        sessionID: UUID? = nil,
        bonusInclusion: BonusInclusion = .included,
        allowanceAwardID: String? = nil
    ) -> ReceivedPayRecord {
        ReceivedPayRecord(
            monthStart: month, workplaceID: workplace, amount: amount,
            basis: basis, sessionID: sessionID,
            bonusInclusion: bonusInclusion, allowanceAwardID: allowanceAwardID
        )
    }

    private func evaluate(
        workplace: UUID, receipts: [ReceivedPayRecord],
        hasIncentives: Bool = false,
        profileNet: Decimal? = 920_000
    ) -> MonthlyReceiptEstimateValidation? {
        MonthlyReceiptEstimateValidation.calculate(
            month: month, workplaceID: workplace, receipts: receipts,
            gross: 1_000_000, hasIncentives: hasIncentives,
            profileNet: profileNet, calendar: calendar
        )
    }

    func testCompleteMonthlyNetReceiptShowsSignedErrors() {
        let workplace = UUID()
        let result = evaluate(workplace: workplace, receipts: [receipt(workplace: workplace)])
        let legacy = EstimatedTakeHomeCalculator.calculate(gross: 1_000_000, shifts: [])
        XCTAssertEqual(result?.actualNet, 900_000)
        XCTAssertEqual(result?.flatRateNet, legacy.net)
        XCTAssertEqual(result?.flatRateError, legacy.net - 900_000)
        XCTAssertEqual(result?.profileError, 20_000)
        XCTAssertEqual(result?.profileAbsoluteError, 20_000)
    }

    func testMissingProfileDoesNotInventProfileError() {
        let workplace = UUID()
        let result = evaluate(
            workplace: workplace, receipts: [receipt(workplace: workplace)],
            profileNet: nil
        )
        XCTAssertNotNil(result)
        XCTAssertNil(result?.profileError)
        XCTAssertNil(result?.profileAbsoluteError)
    }

    func testIncentiveReceiptMustExplicitlyIncludeBonuses() {
        let workplace = UUID()
        let only = receipt(workplace: workplace, bonusInclusion: .unknown)
        XCTAssertNil(evaluate(workplace: workplace, receipts: [only], hasIncentives: true))
        XCTAssertNotNil(evaluate(workplace: workplace, receipts: [only], hasIncentives: false))
    }

    func testGrossDailyAndSeparateAllowanceCannotBeCompared() {
        let workplace = UUID()
        XCTAssertNil(evaluate(
            workplace: workplace, receipts: [receipt(workplace: workplace, basis: .gross)]
        ))
        XCTAssertNil(evaluate(
            workplace: workplace, receipts: [receipt(workplace: workplace, sessionID: UUID())]
        ))
        XCTAssertNil(evaluate(
            workplace: workplace,
            receipts: [receipt(workplace: workplace, allowanceAwardID: "award")]
        ))
        XCTAssertNil(evaluate(
            workplace: workplace,
            receipts: [receipt(workplace: workplace), receipt(workplace: workplace, amount: 20_000)]
        ))
    }

    func testDifferentWorkplaceAndNegativeReceiptAreRejected() {
        let workplace = UUID()
        XCTAssertNil(evaluate(workplace: workplace, receipts: [receipt(workplace: UUID())]))
        XCTAssertNil(evaluate(workplace: workplace, receipts: [
            receipt(workplace: workplace, amount: -1)
        ]))
    }

    func testReceiptsFromOtherMonthsAreExcluded() {
        let workplace = UUID()
        let november = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        let outside = ReceivedPayRecord(
            monthStart: november, workplaceID: workplace, amount: 1_000,
            basis: .net
        )
        let result = evaluate(
            workplace: workplace,
            receipts: [receipt(workplace: workplace), outside]
        )
        XCTAssertNotNil(result)
    }
}

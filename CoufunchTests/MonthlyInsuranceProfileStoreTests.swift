import XCTest
@testable import Coufunch

final class MonthlyInsuranceProfileStoreTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return value
    }

    func testProfileIsolatedAcrossWorkplacesAndMonths() {
        let first = UUID()
        let second = UUID()
        let october = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1))!
        let november = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        let key = MonthlyInsuranceProfileStore.key(
            workplaceID: first, month: october, field: .pensionBase, calendar: calendar
        )
        XCTAssertNotEqual(key, MonthlyInsuranceProfileStore.key(
            workplaceID: second, month: october, field: .pensionBase, calendar: calendar
        ))
        XCTAssertNotEqual(key, MonthlyInsuranceProfileStore.key(
            workplaceID: first, month: november, field: .pensionBase, calendar: calendar
        ))
        XCTAssertNotEqual(key, MonthlyInsuranceProfileStore.key(
            workplaceID: first, month: october, field: .healthBase, calendar: calendar
        ))
    }

    func testUnknownAndLegacyGlobalSettingsAreNotSilentlyUsed() {
        let suite = "CoufunchMonthlyInsuranceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let workplace = UUID()
        let month = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1))!
        defaults.set("enrolled", forKey: "insurance.pensionEnrollment")
        defaults.set("1000000", forKey: "insurance.pensionBase")
        XCTAssertEqual(MonthlyInsuranceProfileStore.enrollment(
            workplaceID: workplace, month: month,
            field: .pensionEnrollment, calendar: calendar, defaults: defaults
        ), .unknown)
        XCTAssertNil(MonthlyInsuranceProfileStore.contributionBase(
            workplaceID: workplace, month: month,
            field: .pensionBase, calendar: calendar, defaults: defaults
        ))
        defaults.set("enrolled", forKey: MonthlyInsuranceProfileStore.key(
            workplaceID: workplace, month: month, field: .pensionEnrollment, calendar: calendar
        ))
        defaults.set("1000000", forKey: MonthlyInsuranceProfileStore.key(
            workplaceID: workplace, month: month, field: .pensionBase, calendar: calendar
        ))
        XCTAssertEqual(MonthlyInsuranceProfileStore.enrollment(
            workplaceID: workplace, month: month,
            field: .pensionEnrollment, calendar: calendar, defaults: defaults
        ), .enrolled)
        XCTAssertEqual(MonthlyInsuranceProfileStore.contributionBase(
            workplaceID: workplace, month: month,
            field: .pensionBase, calendar: calendar, defaults: defaults
        ), Decimal(1_000_000))
    }
}

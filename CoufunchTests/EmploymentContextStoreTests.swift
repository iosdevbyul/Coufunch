import XCTest
@testable import Coufunch

final class EmploymentContextStoreTests: XCTestCase {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return result
    }

    func testKeysAreScopedByWorkplaceAndMonth() {
        let first = UUID()
        let second = UUID()
        let october = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1))!
        let november = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        let key = EmploymentContextStore.key(
            workplaceID: first, month: october, field: "previousMonth", calendar: calendar
        )
        XCTAssertEqual(key, EmploymentContextStore.key(
            workplaceID: first,
            month: calendar.date(from: DateComponents(year: 2026, month: 10, day: 26))!,
            field: "previousMonth", calendar: calendar
        ))
        XCTAssertNotEqual(key, EmploymentContextStore.key(
            workplaceID: second, month: october, field: "previousMonth", calendar: calendar
        ))
        XCTAssertNotEqual(key, EmploymentContextStore.key(
            workplaceID: first, month: november, field: "previousMonth", calendar: calendar
        ))
    }

    func testMissingAndLegacyGlobalAnswersRemainUnknown() {
        let suite = "CoufunchEmploymentContextTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("yes", forKey: "insurance.previousMonthEmployment")
        let workplace = UUID()
        let month = Date(timeIntervalSince1970: 1_780_000_000)
        XCTAssertNil(EmploymentContextStore.previousMonthEmployment(
            workplaceID: workplace, month: month, calendar: calendar, defaults: defaults
        ))
        defaults.set("no", forKey: EmploymentContextStore.key(
            workplaceID: workplace, month: month, field: "previousMonth", calendar: calendar
        ))
        XCTAssertEqual(EmploymentContextStore.previousMonthEmployment(
            workplaceID: workplace, month: month, calendar: calendar, defaults: defaults
        ), false)
    }
}

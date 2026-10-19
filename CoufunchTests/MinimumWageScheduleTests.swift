import XCTest
@testable import Coufunch

final class MinimumWageScheduleTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return value
    }

    func testAutomaticWageSwitchAtNewYear() {
        let old = calendar.date(from: DateComponents(year: 2026, month: 12, day: 31, hour: 19))!
        let current = calendar.date(from: DateComponents(year: 2027, month: 1, day: 1, hour: 0))!
        XCTAssertEqual(MinimumWageSchedule.hourlyRate(for: old, calendar: calendar), 10_320)
        XCTAssertEqual(MinimumWageSchedule.hourlyRate(for: current, calendar: calendar), 10_700)
    }

    func testUnknownYearCannotSilentlyUseStaleRate() {
        let date = calendar.date(from: DateComponents(year: 2028, month: 1, day: 1))!
        XCTAssertNil(MinimumWageSchedule.hourlyRate(for: date, calendar: calendar))
    }
}

import XCTest
@testable import Coufunch

@MainActor
final class KoreanHolidayIntegrationTests: XCTestCase {
    private var seoul: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }

    private func date(_ month: Int, _ day: Int, _ hour: Int = 19) -> Date {
        seoul.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    func testVerifiedSubstituteHolidaysAvailableWithoutNetwork() {
        let store = KoreanPublicHolidayStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        for (month, day) in [(3, 2), (5, 25), (8, 17), (10, 5)] {
            XCTAssertTrue(store.isPublicHoliday(date(month, day)), "Missing substitute holiday")
            XCTAssertNotNil(store.names[String(format: "2026-%02d-%02d", month, day)])
        }
        XCTAssertTrue(store.isPublicHoliday(date(6, 3)))
    }

    func testHolidayOvernightShiftPaidThroughNextMorning() {
        let store = KoreanPublicHolidayStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let start = date(10, 5)
        let end = seoul.date(byAdding: .hour, value: 9, to: start)!
        let session = WorkSession(workplaceID: UUID(), startAt: start, endAt: end,
                                  hourlyRateSnapshot: 10_320)
        XCTAssertEqual(HolidayWorkMinutes.calculate(session: session, breaks: [],
            holidayDates: store.dates), 540)
    }

    func testRegularDayBeforeSubstituteHolidayIsNotPaidAsHoliday() {
        let store = KoreanPublicHolidayStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let start = date(10, 4)
        let session = WorkSession(workplaceID: UUID(), startAt: start,
            endAt: seoul.date(byAdding: .hour, value: 9, to: start)!,
            hourlyRateSnapshot: 10_320)
        XCTAssertEqual(HolidayWorkMinutes.calculate(session: session, breaks: [],
            holidayDates: store.dates), 0)
    }
}

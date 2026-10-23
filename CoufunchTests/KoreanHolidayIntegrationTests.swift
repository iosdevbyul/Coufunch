import XCTest
import NetworkKit
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


    func testHistoricalYearFetchedWithNetworkKitAndCached() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let client = StubHolidayClient()
        client.payload = """
        [{"date":"2020-01-01","localName":"New Year's Day","name":"New Year's Day","types":["Public"]},
         {"date":"2020-01-02","localName":"Observance","name":"Observance","types":["Observance"]}]
        """.data(using: .utf8)!
        let store = KoreanPublicHolidayStore(defaults: defaults, networkClient: client)
        await store.load(year: 2020)
        XCTAssertEqual(client.requestedPath, "api/v3/PublicHolidays/2020/KR")
        XCTAssertEqual(store.names["2020-01-01"], "New Year's Day")
        XCTAssertTrue(store.loadedYears.contains(2020))
        XCTAssertFalse(store.dates.contains("2020-01-02"))
        XCTAssertTrue((defaults.stringArray(forKey: "KRPublicHolidays.2020") ?? []).contains("2020-01-01"))
    }

    func testCachedYearRemainsAvailableAfterNetworkFailure() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(["2023-10-03"], forKey: "KRPublicHolidays.2023")
        defaults.set(["2023-10-03": "National Foundation Day"], forKey: "KRPublicHolidayNames.2023")
        let client = StubHolidayClient()
        client.shouldFail = true
        let store = KoreanPublicHolidayStore(defaults: defaults, networkClient: client)
        await store.load(year: 2023)
        XCTAssertTrue(store.dates.contains("2023-10-03"))
        XCTAssertEqual(store.names["2023-10-03"], "National Foundation Day")
        XCTAssertNotNil(store.errorMessage)
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

private final class StubHolidayClient: NetworkClient, @unchecked Sendable {
    var requestedPath: String?
    var payload = Data()
    var shouldFail = false

    func request<T: Decodable>(endpoint: any Endpoint, responseType: T.Type) async throws -> T {
        requestedPath = endpoint.path
        if shouldFail { throw URLError(.notConnectedToInternet) }
        return try JSONDecoder().decode(T.self, from: payload)
    }
}

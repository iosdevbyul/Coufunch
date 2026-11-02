import XCTest
import SwiftData
@testable import Coufunch

@MainActor
final class SessionEntryPersistenceTests: XCTestCase {
    func testOvernightSessionAndBreakAreStoredAgainstStartDate() throws {
        let schema = Schema([Workplace.self, WorkplacePaySettings.self, WorkSession.self, WorkBreak.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext
        let workplace = Workplace(name: "User-selected workplace")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 19))!
        let end = calendar.date(byAdding: .hour, value: 9, to: start)!
        let session = WorkSession(workplaceID: workplace.id, startAt: start,
                                  endAt: end, status: .completed,
                                  hourlyRateSnapshot: 10_320)
        context.insert(workplace)
        context.insert(session)
        context.insert(WorkBreak(
            sessionID: session.id,
            startAt: calendar.date(byAdding: .hour, value: 3, to: start)!,
            endAt: calendar.date(byAdding: .hour, value: 4, to: start)!
        ))
        try context.save()

        let sessions = try context.fetch(FetchDescriptor<WorkSession>())
        let breaks = try context.fetch(FetchDescriptor<WorkBreak>())
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(breaks.count, 1)
        XCTAssertTrue(calendar.isDate(sessions[0].startAt, inSameDayAs: start))
        XCTAssertFalse(calendar.isDate(sessions[0].endAt!, inSameDayAs: start))
        XCTAssertEqual(breaks[0].sessionID, sessions[0].id)
        XCTAssertEqual(try WorkPayCalculator.calculate(session: sessions[0], breaks: breaks, calendar: calendar).total, 108_360)
    }
    func testLatestSavedSessionTimesAndBreaksAreReused() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        func date(_ day: Int, _ hour: Int) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
        }

        let workplaceID = UUID()
        let older = WorkSession(
            workplaceID: workplaceID, startAt: date(1, 9), endAt: date(1, 18),
            recordedAt: date(1, 19)
        )
        let newest = WorkSession(
            workplaceID: workplaceID, startAt: date(2, 19), endAt: date(3, 4),
            recordedAt: date(2, 20)
        )
        let oldBreak = WorkBreak(sessionID: older.id, startAt: date(1, 12), endAt: date(1, 13))
        let latestBreak = WorkBreak(sessionID: newest.id, startAt: date(2, 23), endAt: date(3, 0))

        let result = WorkSessionEntryDefaults.mostRecentlySaved(
            sessions: [older, newest], breaks: [oldBreak, latestBreak], calendar: calendar
        )
        XCTAssertEqual(result?.work.start, 1140)
        XCTAssertEqual(result?.work.end, 1680)
        XCTAssertEqual(result?.breaks.count, 1)
        XCTAssertEqual(result?.breaks.first?.start, 1380)
        XCTAssertEqual(result?.breaks.first?.end, 1440)
    }

    func testNoSavedSessionsLeavesEntryDefaultsUntouched() {
        XCTAssertNil(WorkSessionEntryDefaults.mostRecentlySaved(sessions: [], breaks: []))
    }

}

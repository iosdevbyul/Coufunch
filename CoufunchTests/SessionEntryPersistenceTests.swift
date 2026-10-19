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
}

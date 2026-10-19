import XCTest
import SwiftData
@testable import Coufunch

@MainActor
final class WorkPersistenceTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Workplace.self,
            WorkSession.self,
            WorkBreak.self,
            IncentiveRule.self,
            ManualIncentive.self
        ])
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }

    func testSessionsPersistAndRemainAssociatedWithStartDate() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let workplace = Workplace(name: "Sample workplace")
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 19))!
        let end = calendar.date(byAdding: .hour, value: 9, to: start)!
        let session = WorkSession(workplaceID: workplace.id, startAt: start, endAt: end, status: .completed)

        context.insert(workplace)
        context.insert(session)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<WorkSession>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.startAt, start)
        XCTAssertTrue(calendar.isDate(fetched[0].startAt, inSameDayAs: start))
        XCTAssertFalse(calendar.isDate(fetched[0].startAt, inSameDayAs: end))
    }

    func testTwoSessionsOnSameStartDateCountOnce() throws {
        let workplaceID = UUID()
        let firstStart = Date(timeIntervalSince1970: 1_792_384_800)
        let nextStart = firstStart.addingTimeInterval(4 * 3600)
        let sessions = [
            WorkSession(workplaceID: workplaceID, startAt: firstStart, status: .completed),
            WorkSession(workplaceID: workplaceID, startAt: nextStart, status: .completed),
            WorkSession(workplaceID: workplaceID, startAt: firstStart, status: .applied)
        ]
        let days = WorkAttendance.uniqueDays(of: sessions, workplaceID: workplaceID, calendar: Calendar(identifier: .gregorian))
        XCTAssertEqual(days.count, 1)
    }

    func testBreakMustFallInsideShift() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let end = start.addingTimeInterval(9 * 3600)
        XCTAssertTrue(WorkSessionValidation.hasValidTimeRange(start: start, end: end))
        XCTAssertTrue(WorkSessionValidation.isValidBreak(
            start: start.addingTimeInterval(3 * 3600),
            end: start.addingTimeInterval(4 * 3600),
            workStart: start,
            workEnd: end
        ))
        XCTAssertFalse(WorkSessionValidation.isValidBreak(
            start: start.addingTimeInterval(-300),
            end: start.addingTimeInterval(300),
            workStart: start,
            workEnd: end
        ))
    }
}

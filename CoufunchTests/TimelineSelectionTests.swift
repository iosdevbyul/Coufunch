import XCTest
@testable import Coufunch

final class TimelineSelectionTests: XCTestCase {
    func testFiveMinuteSnapping() {
        XCTAssertEqual(TimelineSelection.snap(1142), 1140)
        XCTAssertEqual(TimelineSelection.snap(1143), 1145)
        XCTAssertEqual(TimelineSelection.snap(-10), 0)
        XCTAssertEqual(TimelineSelection.snap(3000), 2880)
    }

    func testOvernightSelection() {
        let result = TimelineSelection.selection(from: 1140, to: 1680)
        XCTAssertEqual(result, TimelineRange(start: 1140, end: 1680))
        XCTAssertEqual(result.duration, 540)
    }

    func testReverseDrag() {
        XCTAssertEqual(TimelineSelection.selection(from: 1680, to: 1140),
                       TimelineRange(start: 1140, end: 1680))
    }

    func testHandleCannotCrossOppositeBoundary() {
        let work = TimelineRange(start: 1140, end: 1680)
        let bounds = TimelineRange(start: 0, end: 2880)
        XCTAssertEqual(TimelineSelection.adjust(work, edge: .start, to: 2000, bounds: bounds).start, 1675)
        XCTAssertEqual(TimelineSelection.adjust(work, edge: .end, to: 100, bounds: bounds).end, 1145)
    }

    func testBreakIsClampedWithinWork() {
        let work = TimelineRange(start: 1140, end: 1680)
        let result = TimelineSelection.contained(
            TimelineRange(start: 100, end: 160), within: work
        )
        XCTAssertEqual(result, TimelineRange(start: 1140, end: 1200))
    }
    func testDraggingColoredRangeMovesWholeShiftInFiveMinuteSteps() {
        let initial = TimelineRange(start: 1140, end: 1680)
        let bounds = TimelineRange(start: 0, end: 2880)
        XCTAssertEqual(TimelineSelection.snapDelta(7), 5)
        XCTAssertEqual(TimelineSelection.snapDelta(-7), -5)
        XCTAssertEqual(
            TimelineSelection.move(initial, by: 15, within: bounds),
            TimelineRange(start: 1155, end: 1695)
        )
        XCTAssertEqual(
            TimelineSelection.move(initial, by: -15, within: bounds),
            TimelineRange(start: 1125, end: 1665)
        )
    }

    func testMovingShiftKeepsDurationAndStaysWithinBounds() {
        let initial = TimelineRange(start: 1140, end: 1680)
        let bounds = TimelineRange(start: 0, end: 2880)
        XCTAssertEqual(
            TimelineSelection.move(initial, by: -5000, within: bounds),
            TimelineRange(start: 0, end: 540)
        )
        XCTAssertEqual(
            TimelineSelection.move(initial, by: 5000, within: bounds),
            TimelineRange(start: 2340, end: 2880)
        )
    }

}

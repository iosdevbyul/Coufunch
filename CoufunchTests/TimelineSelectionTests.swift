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

    func testMoveWithinSixToSixWindowKeepsDuration() {
        let bounds = TimelineRange(start: 360, end: 1800)
        let original = TimelineRange(start: 1140, end: 1680)
        let shifted = TimelineSelection.move(original, by: -300, within: bounds)
        XCTAssertEqual(shifted, TimelineRange(start: 840, end: 1380))
        let capped = TimelineSelection.move(original, by: 500, within: bounds)
        XCTAssertEqual(capped, TimelineRange(start: 1260, end: 1800))
        XCTAssertEqual(capped.duration, original.duration)
    }

    func testTwentyFourHourVisibleWindowSupportsNextDaySix() {
        let bounds = TimelineRange(start: 360, end: 1800)
        XCTAssertEqual(bounds.duration, 24 * 60)
        XCTAssertEqual(TimelineSelection.selection(from: 360, to: 1800), bounds)
    }

    func testResizingEdgesChangesDurationWithoutMovingOppositeEdge() {
        let bounds = TimelineRange(start: 360, end: 1800)
        let original = TimelineRange(start: 540, end: 1080)
        let startMoved = TimelineSelection.adjust(original, edge: .start,
                                                  to: 600, bounds: bounds)
        XCTAssertEqual(startMoved, TimelineRange(start: 600, end: 1080))
        let endMoved = TimelineSelection.adjust(original, edge: .end,
                                                to: 1200, bounds: bounds)
        XCTAssertEqual(endMoved, TimelineRange(start: 540, end: 1200))
    }

    func testEdgeResizeClampsAtMinimumFiveMinutesAndVisibleBounds() {
        let bounds = TimelineRange(start: 360, end: 1800)
        let original = TimelineRange(start: 540, end: 1080)
        XCTAssertEqual(TimelineSelection.adjust(original, edge: .start,
                                                to: 2000, bounds: bounds),
                       TimelineRange(start: 1075, end: 1080))
        XCTAssertEqual(TimelineSelection.adjust(original, edge: .end,
                                                to: 0, bounds: bounds),
                       TimelineRange(start: 540, end: 545))
        XCTAssertEqual(TimelineSelection.adjust(original, edge: .start,
                                                to: 0, bounds: bounds).start, 360)
        XCTAssertEqual(TimelineSelection.adjust(original, edge: .end,
                                                to: 2000, bounds: bounds).end, 1800)
    }

    func testBreakIsClampedToGreenWorkInterval() {
        let work = TimelineRange(start: 540, end: 1080)
        let rest = TimelineRange(start: 720, end: 780)
        let bounds = TimelineSelection.breakBounds(work: work, breaks: [rest], index: 0)
        XCTAssertEqual(bounds, work)
        XCTAssertEqual(TimelineSelection.move(rest, by: -500, within: work),
                       TimelineRange(start: 540, end: 600))
        XCTAssertEqual(TimelineSelection.move(rest, by: 500, within: work),
                       TimelineRange(start: 1020, end: 1080))
        XCTAssertEqual(TimelineSelection.adjust(rest, edge: .end, to: 1800, bounds: work).end,
                       1080)
    }

    func testBreakCannotOverlapAnotherBreakWhenMovedOrResized() {
        let work = TimelineRange(start: 540, end: 1080)
        let first = TimelineRange(start: 660, end: 720)
        let second = TimelineRange(start: 840, end: 900)
        let bounds = TimelineSelection.breakBounds(
            work: work, breaks: [first, second], index: 0
        )!
        XCTAssertEqual(bounds, TimelineRange(start: 540, end: 840))
        XCTAssertEqual(TimelineSelection.move(first, by: 500, within: bounds),
                       TimelineRange(start: 780, end: 840))
        XCTAssertEqual(TimelineSelection.adjust(first, edge: .end, to: 1000, bounds: bounds).end,
                       840)
    }

    func testInvalidBreakIndexDoesNotProduceBounds() {
        XCTAssertNil(TimelineSelection.breakBounds(
            work: TimelineRange(start: 540, end: 1080), breaks: [], index: 0
        ))
    }

    func testTwentySixHourRulerSupportsNextDayEight() {
        let visible = TimelineRange(start: 360, end: 1920)
        XCTAssertEqual(visible.duration, 26 * 60)
        let work = TimelineRange(start: 1380, end: 1920)
        XCTAssertEqual(TimelineSelection.move(work, by: 100, within: visible), work)
        XCTAssertEqual(TimelineSelection.adjust(work, edge: .end, to: 2000, bounds: visible).end, 1920)
        XCTAssertEqual(TimelineSelection.contained(
            TimelineRange(start: 1860, end: 1980), within: visible
        ), TimelineRange(start: 1800, end: 1920))
    }

}

import Foundation

/// Minute offsets from the beginning of the work's attributed calendar date.
/// The editor spans 48 hours so shifts crossing midnight remain visible.
struct TimelineRange: Equatable {
    var start: Int
    var end: Int

    var duration: Int { end - start }
}

enum TimelineSelection {
    static let maximumMinute = 48 * 60
    static let step = 5

    static func snap(_ value: Double) -> Int {
        min(maximumMinute, max(0, Int((value / Double(step)).rounded()) * step))
    }

    static func selection(from anchor: Int, to current: Int) -> TimelineRange {
        let a = snap(Double(anchor))
        let b = snap(Double(current))
        let lower = min(a, b)
        let start = min(lower, maximumMinute - step)
        return TimelineRange(start: start, end: min(maximumMinute, max(start + step, max(a, b))))
    }

    static func adjust(_ range: TimelineRange, edge: Edge, to minute: Int, bounds: TimelineRange) -> TimelineRange {
        let snapped = snap(Double(minute))
        switch edge {
        case .start:
            return .init(start: min(range.end - step, max(bounds.start, snapped)), end: range.end)
        case .end:
            return .init(start: range.start, end: max(range.start + step, min(bounds.end, snapped)))
        }
    }

    static func contained(_ range: TimelineRange, within bounds: TimelineRange) -> TimelineRange? {
        guard bounds.duration >= step else { return nil }
        let length = min(max(step, range.duration), bounds.duration)
        let start = min(max(range.start, bounds.start), bounds.end - length)
        return .init(start: start, end: start + length)
    }

    enum Edge { case start, end }
}

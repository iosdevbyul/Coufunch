import Foundation

enum MinimumWageSchedule {
    // Official Ministry of Employment and Labor wage notices.
    static let hourlyByYear: [Int: Decimal] = [
        2026: 10_320,
        2027: 10_700
    ]

    static func hourlyRate(for startAt: Date, calendar: Calendar = .current) -> Decimal? {
        hourlyByYear[calendar.component(.year, from: startAt)]
    }
}

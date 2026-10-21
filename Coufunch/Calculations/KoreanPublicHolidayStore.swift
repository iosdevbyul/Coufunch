import Foundation
import Combine

/// Korean public holidays are inputs for estimated pay, not evidence of employer eligibility.
/// 2026 fallback dates are cross-checked with Korea Customs Service's published calendar.
/// Other years use the remote feed and last-known cached results only.
@MainActor
final class KoreanPublicHolidayStore: ObservableObject {
    @Published private(set) var dates: Set<String> = []
    @Published private(set) var names: [String: String] = [:]
    @Published private(set) var loadedYears: Set<Int> = []
    @Published private(set) var errorMessage: String?

    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        applyVerified2026()
    }

    // Officially listed 2026 holidays, including substitute days and election day.
    private static let verified2026: [String: String] = [
        "2026-01-01": "New Year's Day",
        "2026-02-16": "Seollal", "2026-02-17": "Seollal",
        "2026-02-18": "Seollal",
        "2026-03-01": "Independence Movement Day",
        "2026-03-02": "Substitute Holiday (March 1)",
        "2026-05-01": "Labor Day",
        "2026-05-05": "Children's Day",
        "2026-05-24": "Buddha's Birthday",
        "2026-05-25": "Substitute Holiday (Buddha's Birthday)",
        "2026-06-03": "Election Day",
        "2026-06-06": "Memorial Day",
        "2026-07-17": "Constitution Day",
        "2026-08-15": "Liberation Day",
        "2026-08-17": "Substitute Holiday (Liberation Day)",
        "2026-09-24": "Chuseok", "2026-09-25": "Chuseok",
        "2026-09-26": "Chuseok",
        "2026-10-03": "National Foundation Day",
        "2026-10-05": "Substitute Holiday (National Foundation Day)",
        "2026-10-09": "Hangeul Day",
        "2026-12-25": "Christmas"
    ]

    private func applyVerified2026() {
        names.merge(Self.verified2026) { _, verified in verified }
        dates.formUnion(Self.verified2026.keys)
        loadedYears.insert(2026)
    }

    func isPublicHoliday(_ date: Date, calendar: Calendar = .current) -> Bool {
        let parts = Self.seoulCalendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day,
              loadedYears.contains(year) else { return false }
        return dates.contains(String(format: "%04d-%02d-%02d", year, month, day))
    }

    func load(year: Int) async {
        let cacheKey = "KRPublicHolidays.\(year)"
        let namesKey = "KRPublicHolidayNames.\(year)"
        if let cached = defaults.array(forKey: cacheKey) as? [String] {
            dates.formUnion(cached)
            loadedYears.insert(year)
        }
        if let cachedNames = defaults.dictionary(forKey: namesKey) as? [String: String] {
            names.merge(cachedNames) { _, new in new }
        }
        if year == 2026 { applyVerified2026() }

        guard let url = URL(string: "https://date.nager.at/api/v3/PublicHolidays/\(year)/KR") else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let holidays = try JSONDecoder().decode([Holiday].self, from: data)
            let publicHolidays = holidays.filter { $0.types.contains("Public") }
            let downloadedDates = Set(publicHolidays.map(\.date))
            let downloadedNames = Dictionary(publicHolidays.map {
                ($0.date, $0.localName.isEmpty ? $0.name : $0.localName)
            }, uniquingKeysWith: { first, _ in first })
            // Replace stale cached records for this year, while preserving verified 2026 dates.
            dates.subtract(dates.filter { $0.hasPrefix("\(year)-") })
            names = names.filter { !$0.key.hasPrefix("\(year)-") }
            dates.formUnion(downloadedDates)
            names.merge(downloadedNames) { _, new in new }
            if year == 2026 { applyVerified2026() }
            defaults.set(Array(dates.filter { $0.hasPrefix("\(year)-") }), forKey: cacheKey)
            defaults.set(names.filter { $0.key.hasPrefix("\(year)-") }, forKey: namesKey)
            loadedYears.insert(year)
            errorMessage = nil
        } catch {
            if !loadedYears.contains(year) {
                errorMessage = "Public holiday data is unavailable for \(year). Holiday pay cannot be verified."
            } else {
                errorMessage = "Holiday data could not be refreshed. Cached or verified dates are shown."
            }
        }
    }

    private struct Holiday: Decodable {
        let date: String
        let localName: String
        let name: String
        let types: [String]
    }

    private static var seoulCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }
}

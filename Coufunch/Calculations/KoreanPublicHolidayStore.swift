import Foundation
import Combine

/// Public holiday dates are data inputs, not proof of individual holiday-pay eligibility.
/// Fetches public KR holidays and preserves a last-known copy for offline use.
@MainActor
final class KoreanPublicHolidayStore: ObservableObject {
    @Published private(set) var dates: Set<String> = []
    @Published private(set) var loadedYears: Set<Int> = []
    @Published private(set) var errorMessage: String?

    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func isPublicHoliday(_ date: Date, calendar: Calendar = .current) -> Bool {
        let local = Self.seoulCalendar
        let parts = local.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day,
              loadedYears.contains(year) else { return false }
        return dates.contains(String(format: "%04d-%02d-%02d", year, month, day))
    }

    func load(year: Int) async {
        if let cached = defaults.array(forKey: "KRPublicHolidays.\(year)") as? [String] {
            dates.formUnion(cached)
            loadedYears.insert(year)
        }
        guard let url = URL(string: "https://date.nager.at/api/v3/PublicHolidays/\(year)/KR") else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let results = try JSONDecoder().decode([Holiday].self, from: data)
            let values = results.map(\.date)
            defaults.set(values, forKey: "KRPublicHolidays.\(year)")
            dates.formUnion(values)
            loadedYears.insert(year)
            errorMessage = nil
        } catch {
            errorMessage = "Holiday data could not be updated. Cached dates may be used."
        }
    }

    private struct Holiday: Decodable { let date: String }
    private static var seoulCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }
}

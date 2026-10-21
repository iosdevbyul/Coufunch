import Foundation

enum HolidayWorkMinutes {
    static func calculate(session: WorkSession, breaks: [WorkBreak], holidayDates: Set<String>) -> Int {
        guard let end = session.endAt, end > session.startAt else { return 0 }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let components = calendar.dateComponents([.year, .month, .day], from: session.startAt)
        let key = String(format: "%04d-%02d-%02d",
            components.year ?? 0, components.month ?? 0, components.day ?? 0)
        guard holidayDates.contains(key) else { return 0 }

        let intervals = breaks.compactMap { rest -> (Date, Date)? in
            let start = max(rest.startAt, session.startAt)
            let finish = min(rest.endAt, end)
            return finish > start ? (start, finish) : nil
        }.sorted { $0.0 < $1.0 }
        var unpaidMinutes = 0
        var coveredUntil = session.startAt
        for (start, finish) in intervals where finish > coveredUntil {
            unpaidMinutes += Int((finish.timeIntervalSince(max(start, coveredUntil)) / 60).rounded())
            coveredUntil = finish
        }
        let shiftMinutes = Int((end.timeIntervalSince(session.startAt) / 60).rounded())
        return max(0, shiftMinutes - unpaidMinutes)
    }
}

import Foundation

enum HolidayWorkMinutes {
    static func calculate(session: WorkSession, breaks: [WorkBreak], holidayDates: Set<String>) -> Int {
        guard let end = session.endAt, end > session.startAt else { return 0 }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        var current = calendar.startOfDay(for: session.startAt)
        var minutes = 0
        while current < end {
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            let components = calendar.dateComponents([.year, .month, .day], from: current)
            let key = String(format: "%04d-%02d-%02d",
                components.year ?? 0, components.month ?? 0, components.day ?? 0)
            if holidayDates.contains(key) {
                let from = max(session.startAt, current)
                let to = min(end, next)
                if to > from {
                    let duration = Int((to.timeIntervalSince(from) / 60).rounded())
                    let intervals = breaks.compactMap { rest -> (Date, Date)? in
                        let start = max(rest.startAt, from)
                        let finish = min(rest.endAt, to)
                        return finish > start ? (start, finish) : nil
                    }.sorted { $0.0 < $1.0 }
                    var overlap = 0
                    var coveredUntil = from
                    for (start, finish) in intervals {
                        if finish > coveredUntil {
                            overlap += Int((finish.timeIntervalSince(max(start, coveredUntil)) / 60).rounded())
                            coveredUntil = finish
                        }
                    }
                    minutes += max(0, duration - overlap)
                }
            }
            current = next
        }
        return minutes
    }
}

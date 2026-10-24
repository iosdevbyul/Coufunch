import Foundation
import UserNotifications

enum PaydayReminderDate {
    static func nextBusinessDay(after shiftStart: Date, holidays: Set<String>, loadedYears: Set<Int>) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        guard let followingDay = calendar.date(byAdding: .day, value: 1,
                                                to: calendar.startOfDay(for: shiftStart)) else { return nil }
        var day = followingDay
        for _ in 0..<15 {
            let parts = calendar.dateComponents([.year, .month, .day, .weekday], from: day)
            guard let year = parts.year, let month = parts.month,
                  let date = parts.day, let weekday = parts.weekday else { return nil }
            guard loadedYears.contains(year) else { return nil }
        let key = String(format: "%04d-%02d-%02d", year, month, date)
            if weekday != 1 && weekday != 7 && !holidays.contains(key) {
                return calendar.date(bySettingHour: 10, minute: 0, second: 0, of: day)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
            day = next
        }
        return nil
    }
}

@MainActor
enum PaydayReminderScheduler {
    private static let prefix = "coufunch.payday."

    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge, .sound])) ?? false
    }

    static func cancelAll() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers:
            pending.map(\.identifier).filter { $0.hasPrefix(prefix) })
    }

    static func synchronize(sessions: [WorkSession], holidays: Set<String>,
                            loadedYears: Set<Int>, now: Date = .now) async {
        guard UserDefaults.standard.bool(forKey: "paydayRemindersEnabled") else {
            await cancelAll()
            return
        }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized ||
              settings.authorizationStatus == .provisional else {
            NSLog("Coufunch payday reminders not scheduled: notification authorization unavailable")
            return
        }

        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers:
            pending.map(\.identifier).filter { $0.hasPrefix(prefix) })

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!

        let upcoming = sessions.filter { $0.status == .completed }
            .compactMap { session -> (String, Date)? in
                guard let due = PaydayReminderDate.nextBusinessDay(
                    after: session.startAt, holidays: holidays, loadedYears: loadedYears),
                      due > now else { return nil }
                let day = calendar.startOfDay(for: due)
                return (String(Int(day.timeIntervalSince1970)), due)
            }
        if upcoming.isEmpty {
            NSLog("Coufunch payday reminders: no eligible future pay dates; check completed shifts and loaded holiday years")
        }
        // A single reminder per pay date, even if multiple completed shifts map to it.
        var seen = Set<String>()
        for (key, date) in upcoming.sorted(by: { $0.1 < $1.1 }) where seen.insert(key).inserted {
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Payday Reminder")
            content.body = String(localized: "Today is payday. Check your payment details.")
            content.sound = .default
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            let request = UNNotificationRequest(identifier: prefix + key,
                                                content: content, trigger: trigger)
            do {
                try await center.add(request)
            } catch {
                NSLog("Coufunch reminder scheduling failed: %@", String(describing: error))
            }
        }
    }
}

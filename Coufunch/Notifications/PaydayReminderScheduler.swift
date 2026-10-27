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
                return calendar.date(bySettingHour: 14, minute: 0, second: 0, of: day)
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
                            workplaces: [Workplace] = [], rules: [IncentiveRule] = [],
                            loadedYears: Set<Int>, now: Date = .now,
                            breaks: [WorkBreak] = [], paySettings: [WorkplacePaySettings] = [],
                            receivedPay: [ReceivedPayRecord] = []) async {
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

        let receivedSessionIDs = Set(receivedPay.compactMap(\.sessionID))
        let upcoming = sessions.filter {
            $0.status == .completed && !receivedSessionIDs.contains($0.id)
        }.compactMap { session -> (session: WorkSession, key: String, due: Date)? in
            guard let due = PaydayReminderDate.nextBusinessDay(
                after: session.startAt, holidays: holidays, loadedYears: loadedYears
            ), due > now else { return nil }
            return (session, String(Int(calendar.startOfDay(for: due).timeIntervalSince1970)), due)
        }
        let byPayDate = Dictionary(grouping: upcoming, by: \.key)
        let specialDates = SpecialAllowancePayday.dueDates(
            sessions: sessions, workplaces: workplaces, rules: rules, calendar: calendar
        ).filter { $0 > now }
        if upcoming.isEmpty && specialDates.isEmpty {
            NSLog("Coufunch payday reminders: no eligible future pay dates; check completed shifts and loaded holiday years")
        }
        var specialSeen = Set<String>()
        for due in specialDates.sorted() {
            let day = calendar.startOfDay(for: due)
            let key = String(Int(day.timeIntervalSince1970))
            guard specialSeen.insert(key).inserted else { continue }
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Special Allowance Payday")
            content.body = String(localized: "You worked six days last week. Today is the expected special allowance payday.")
            content.sound = .default
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: due)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            do {
                try await center.add(UNNotificationRequest(
                    identifier: prefix + "special." + key, content: content, trigger: trigger))
            } catch {
                NSLog("Coufunch special allowance reminder scheduling failed: %@", String(describing: error))
            }
        }
        // A single reminder per pay date, even if multiple completed shifts map to it.
        var seen = Set<String>()
        for group in byPayDate.values.sorted(by: {
            ($0.first?.due ?? .distantFuture) < ($1.first?.due ?? .distantFuture)
        }) {
            guard let first = group.first else { continue }
            let key = first.key
            let date = first.due
            guard seen.insert(key).inserted else { continue }
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Payday Reminder")
            // Do not invent a monetary amount when a shift cannot be priced.
            let amounts: [Decimal]? = {
                var results: [Decimal] = []
                for item in group {
                    let setting = paySettings.first { $0.workplaceID == item.session.workplaceID }
                    let sessionBreaks = breaks.filter { $0.sessionID == item.session.id }
                    guard let result = try? WorkPayCalculator.calculate(
                        session: item.session, breaks: sessionBreaks, calendar: calendar,
                        nightPremiumEnabled: item.session.nightPremiumSnapshot ?? setting?.nightPremiumEnabled ?? true,
                        overtimePremiumEnabled: item.session.overtimePremiumSnapshot ?? setting?.overtimePremiumEnabled ?? true,
                        holidayPaidMinutes: HolidayWorkMinutes.calculate(
                            session: item.session, breaks: sessionBreaks, holidayDates: holidays
                        )
                    ) else { return nil }
                    results.append(result.total)
                }
                return results
            }()
            if let amounts, !amounts.isEmpty {
                let gross = amounts.reduce(Decimal.zero, +)
                let net = EstimatedTakeHomeCalculator.calculate(gross: gross, shifts: []).net
                let won = NSDecimalNumber(decimal: net).int64Value.formatted()
                content.body = "오늘 예상 급여 입금일입니다. 세후 추정액: \(won)원 (수당·세금 등 실제 지급액과 차이 가능). 입금 후 앱에서 수령액을 기록하세요."
            } else {
                content.body = "오늘 예상 급여 입금일입니다. 입금 후 앱에서 실제 수령액을 기록하세요."
            }
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

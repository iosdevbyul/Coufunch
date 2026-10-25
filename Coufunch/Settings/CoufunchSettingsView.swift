import SwiftUI
import SwiftData

struct CoufunchSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Workplace.name) private var workplaces: [Workplace]
    @AppStorage("paydayRemindersEnabled") private var remindersEnabled = false
    @StateObject private var holidays = KoreanPublicHolidayStore()
    @Query private var sessions: [WorkSession]
    @Query private var rules: [IncentiveRule]
    @State private var isUpdating = false
    @State private var permissionMessage: String?
    @State private var weeklyStartError: String?

    var body: some View {
        Form {
            Section("Weekly Bonus Period") {
                Text("Weekly attendance bonuses are calculated within each workplace's selected seven-day period. The default is Sunday through Saturday.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                ForEach(workplaces) { workplace in
                    Picker(workplace.name, selection: Binding(
                        get: { (1...7).contains(workplace.weekStartWeekday) ? workplace.weekStartWeekday : 1 },
                        set: { saveWeekStart($0, for: workplace) }
                    )) {
                        Text("Sunday").tag(1)
                        Text("Monday").tag(2)
                        Text("Tuesday").tag(3)
                        Text("Wednesday").tag(4)
                        Text("Thursday").tag(5)
                        Text("Friday").tag(6)
                        Text("Saturday").tag(7)
                    }
                }

                if workplaces.isEmpty {
                    Text("Add a workplace to configure its bonus week.")
                        .foregroundStyle(.secondary)
                }
                if let weeklyStartError {
                    Text(LocalizedStringKey(weeklyStartError))
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
                Text("Weekly 5-day and 6-day bonuses use this period. Monthly 15-day bonuses continue to use calendar months.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Notifications") {
                Toggle("Payday Reminders", isOn: Binding(
                    get: { remindersEnabled },
                    set: { enabled in Task { await updateReminders(enabled) } }
                ))
                .disabled(isUpdating)
                Text("Remind me at 10 AM on the next Korean business day after a completed shift.")
                    .font(.footnote).foregroundStyle(.secondary)
                if let permissionMessage {
                    Text(LocalizedStringKey(permissionMessage)).font(.footnote).foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle("Settings")
    }

    private func saveWeekStart(_ weekday: Int, for workplace: Workplace) {
        guard (1...7).contains(weekday) else { return }
        let previous = workplace.weekStartWeekday
        workplace.weekStartWeekday = weekday
        do {
            try modelContext.save()
            weeklyStartError = nil
        } catch {
            workplace.weekStartWeekday = previous
            weeklyStartError = "Couldn't save the weekly bonus start day."
        }
    }

    private func updateReminders(_ enabled: Bool) async {
        isUpdating = true
        defer { isUpdating = false }
        if !enabled {
            remindersEnabled = false
            await PaydayReminderScheduler.cancelAll()
            permissionMessage = nil
            return
        }
        guard await PaydayReminderScheduler.requestAuthorization() else {
            remindersEnabled = false
            permissionMessage = "Notifications are disabled. Allow them in iPhone Settings."
            return
        }
        remindersEnabled = true
        permissionMessage = nil
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let year = calendar.component(.year, from: Date())
        await holidays.load(year: year)
        await holidays.load(year: year + 1)
        await PaydayReminderScheduler.synchronize(sessions: sessions,
            holidays: holidays.dates, workplaces: workplaces, rules: rules,
            loadedYears: holidays.loadedYears)
    }
}

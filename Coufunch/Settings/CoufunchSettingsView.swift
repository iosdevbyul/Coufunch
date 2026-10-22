import SwiftUI
import SwiftData

struct CoufunchSettingsView: View {
    @AppStorage("paydayRemindersEnabled") private var remindersEnabled = false
    @StateObject private var holidays = KoreanPublicHolidayStore()
    @Query private var sessions: [WorkSession]
    @State private var isUpdating = false
    @State private var permissionMessage: String?

    var body: some View {
        Form {
            Section("Notifications") {
                Toggle("Payday Reminders", isOn: Binding(
                    get: { remindersEnabled },
                    set: { enabled in Task { await updateReminders(enabled) } }
                ))
                .disabled(isUpdating)
                Text("Remind me at 10 AM on the next Korean business day after a completed shift.")
                    .font(.footnote).foregroundStyle(.secondary)
                if let permissionMessage {
                    Text(permissionMessage).font(.footnote).foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle("Settings")
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
            holidays: holidays.dates, loadedYears: holidays.loadedYears)
    }
}

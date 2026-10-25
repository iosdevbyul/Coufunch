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
    @AppStorage("insurance.pensionEnrollment") private var pensionEnrollment = "unknown"
    @AppStorage("insurance.healthEnrollment") private var healthEnrollment = "unknown"
    @AppStorage("insurance.pensionBase") private var pensionBase = ""
    @AppStorage("insurance.healthBase") private var healthBase = ""
    @State private var employmentMonth = Date()

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

            Section("Insurance Estimate Profile") {
                Text("These settings only affect the separate insurance preview. They do not change recorded bank deposits or existing pay reconciliation.")
                    .font(.footnote).foregroundStyle(.secondary)
                DatePicker("Employment Context Month", selection: $employmentMonth, displayedComponents: .date)
                ForEach(workplaces) { workplace in
                    WorkplaceEmploymentContextEditor(
                        workplace: workplace,
                        month: employmentMonth
                    )
                }
                Text("Employment answers are stored separately for each workplace and month. Previous global answers are not reused.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("Insurance settings are saved separately for each workplace and month. Previous global settings are not reused.")
                    .font(.footnote).foregroundStyle(.secondary)
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

private struct WorkplaceEmploymentContextEditor: View {
    let workplace: Workplace
    let month: Date
    @State private var previous = "unknown"
    @State private var firstDay = "unknown"
    @State private var pensionEnrollment = "unknown"
    @State private var healthEnrollment = "unknown"
    @State private var pensionBase = ""
    @State private var healthBase = ""

    private var previousKey: String {
        EmploymentContextStore.key(
            workplaceID: workplace.id, month: month,
            field: "previousMonth", calendar: .current
        )
    }

    private var firstDayKey: String {
        EmploymentContextStore.key(
            workplaceID: workplace.id, month: month,
            field: "startedOnFirstDay", calendar: .current
        )
    }

    private func insuranceKey(_ field: MonthlyInsuranceProfileStore.Field) -> String {
        MonthlyInsuranceProfileStore.key(
            workplaceID: workplace.id, month: month, field: field, calendar: .current
        )
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text(workplace.name).font(.headline)
            Picker("Employed in Previous Month", selection: $previous) {
                Text("Unknown").tag("unknown")
                Text("Yes").tag("yes")
                Text("No").tag("no")
            }
            Picker("Started Employment on Day One", selection: $firstDay) {
                Text("Unknown").tag("unknown")
                Text("Yes").tag("yes")
                Text("No").tag("no")
            }
            Picker("National Pension Enrollment", selection: $pensionEnrollment) {
                Text("Unknown").tag("unknown")
                Text("Enrolled").tag("enrolled")
                Text("Not Enrolled").tag("notEnrolled")
            }
            Picker("Health Insurance Enrollment", selection: $healthEnrollment) {
                Text("Unknown").tag("unknown")
                Text("Enrolled").tag("enrolled")
                Text("Not Enrolled").tag("notEnrolled")
            }
            TextField("Pension Contribution Base (KRW)", text: $pensionBase)
                .keyboardType(.numberPad)
            TextField("Health Contribution Base (KRW)", text: $healthBase)
                .keyboardType(.numberPad)
        }
        .onAppear(perform: load)
        .onChange(of: month) { _, _ in load() }
        .onChange(of: previous) { _, value in
            UserDefaults.standard.set(value, forKey: previousKey)
        }
        .onChange(of: firstDay) { _, value in
            UserDefaults.standard.set(value, forKey: firstDayKey)
        }
    }

        .onChange(of: pensionEnrollment) { _, value in
            UserDefaults.standard.set(value, forKey: insuranceKey(.pensionEnrollment))
        }
        .onChange(of: healthEnrollment) { _, value in
            UserDefaults.standard.set(value, forKey: insuranceKey(.healthEnrollment))
        }
        .onChange(of: pensionBase) { _, value in
            UserDefaults.standard.set(value, forKey: insuranceKey(.pensionBase))
        }
        .onChange(of: healthBase) { _, value in
            UserDefaults.standard.set(value, forKey: insuranceKey(.healthBase))
        }

    private func load() {
        previous = UserDefaults.standard.string(forKey: previousKey) ?? "unknown"
        firstDay = UserDefaults.standard.string(forKey: firstDayKey) ?? "unknown"
        pensionEnrollment = UserDefaults.standard.string(forKey: insuranceKey(.pensionEnrollment)) ?? "unknown"
        healthEnrollment = UserDefaults.standard.string(forKey: insuranceKey(.healthEnrollment)) ?? "unknown"
        pensionBase = UserDefaults.standard.string(forKey: insuranceKey(.pensionBase)) ?? ""
        healthBase = UserDefaults.standard.string(forKey: insuranceKey(.healthBase)) ?? ""
    }
}

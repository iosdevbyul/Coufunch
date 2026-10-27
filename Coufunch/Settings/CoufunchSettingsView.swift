import SwiftUI
import SwiftData
import UniformTypeIdentifiers

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
    @State private var employmentMonth = Date()
    @State private var exportDocument: CoufunchBackupDocument?
    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var pendingRestore: CoufunchBackupArchive?
    @State private var showingRestoreConfirmation = false
    @State private var backupMessage: String?

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

            Section("데이터 백업 및 복원") {
                Text("근무 기록, 휴게시간, 사업장, 급여 설정, 수당, 실제 입금 내역과 월별 보험·고용·급여 검증 설정을 JSON 파일로 저장하거나 가져옵니다.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("백업 파일 내보내기") {
                    do {
                        exportDocument = CoufunchBackupDocument(
                            archive: try CoufunchBackupStore.create(from: modelContext)
                        )
                        showingExporter = true
                    } catch {
                        backupMessage = error.localizedDescription
                    }
                }
                Button("백업 파일 가져오기") {
                    showingImporter = true
                }
                Text("복원은 파일의 기록을 추가하며, 같은 ID의 기존 기록과 이미 설정된 월별 값을 덮어쓰지 않습니다. iPhone 알림 권한 및 알림 사용 여부는 백업되지 않습니다. v1 백업 파일도 가져올 수 있습니다.")
                    .font(.footnote).foregroundStyle(.secondary)
                if let backupMessage {
                    Text(backupMessage)
                        .font(.footnote).foregroundStyle(.secondary)
                }
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
        .fileExporter(isPresented: $showingExporter,
                      document: exportDocument,
                      contentType: .json,
                      defaultFilename: "Coufunch-Backup") { result in
            switch result {
            case .success: backupMessage = "백업 파일을 저장했습니다."
            case .failure(let error): backupMessage = error.localizedDescription
            }
            exportDocument = nil
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                pendingRestore = try CoufunchBackupStore.decode(data)
                showingRestoreConfirmation = true
            } catch {
                backupMessage = error.localizedDescription
            }
        }
        .confirmationDialog(
            "기존 기록은 그대로 두고 백업 기록을 추가할까요?",
            isPresented: $showingRestoreConfirmation,
            titleVisibility: .visible
        ) {
            Button("복원 실행") {
                guard let pendingRestore else { return }
                do {
                    let inserted = try CoufunchBackupStore.restore(pendingRestore, into: modelContext)
                    backupMessage = "\\(inserted)건을 추가했습니다. 기존 기록은 유지했습니다."
                } catch {
                    backupMessage = error.localizedDescription
                }
                self.pendingRestore = nil
            }
            Button("취소", role: .cancel) { pendingRestore = nil }
        } message: {
            Text("백업 파일의 총 \\(pendingRestore?.recordCount ?? 0)건 중 이미 존재하는 ID는 건너뜁니다. 복원 전 별도의 백업을 먼저 저장하는 것을 권장합니다.")
        }
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
    @State private var loadedMonthKey = ""

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
            if loadedMonthKey == EmploymentContextStore.monthKey(month, calendar: .current) { UserDefaults.standard.set(value, forKey: previousKey) }
        }
        .onChange(of: firstDay) { _, value in
            if loadedMonthKey == EmploymentContextStore.monthKey(month, calendar: .current) { UserDefaults.standard.set(value, forKey: firstDayKey) }
        }
        .onChange(of: pensionEnrollment) { _, value in
            if loadedMonthKey == EmploymentContextStore.monthKey(month, calendar: .current) { UserDefaults.standard.set(value, forKey: insuranceKey(.pensionEnrollment)) }
        }
        .onChange(of: healthEnrollment) { _, value in
            if loadedMonthKey == EmploymentContextStore.monthKey(month, calendar: .current) { UserDefaults.standard.set(value, forKey: insuranceKey(.healthEnrollment)) }
        }
        .onChange(of: pensionBase) { _, value in
            if loadedMonthKey == EmploymentContextStore.monthKey(month, calendar: .current) { UserDefaults.standard.set(value, forKey: insuranceKey(.pensionBase)) }
        }
        .onChange(of: healthBase) { _, value in
            if loadedMonthKey == EmploymentContextStore.monthKey(month, calendar: .current) { UserDefaults.standard.set(value, forKey: insuranceKey(.healthBase)) }
        }
    }

    private func load() {
        loadedMonthKey = ""
        previous = UserDefaults.standard.string(forKey: previousKey) ?? "unknown"
        firstDay = UserDefaults.standard.string(forKey: firstDayKey) ?? "unknown"
        pensionEnrollment = UserDefaults.standard.string(forKey: insuranceKey(.pensionEnrollment)) ?? "unknown"
        healthEnrollment = UserDefaults.standard.string(forKey: insuranceKey(.healthEnrollment)) ?? "unknown"
        pensionBase = UserDefaults.standard.string(forKey: insuranceKey(.pensionBase)) ?? ""
        healthBase = UserDefaults.standard.string(forKey: insuranceKey(.healthBase)) ?? ""
        loadedMonthKey = EmploymentContextStore.monthKey(month, calendar: .current)
    }
}

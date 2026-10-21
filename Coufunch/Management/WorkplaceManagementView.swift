import SwiftUI
import SwiftData
import WakTrainerDesignSystem

struct WorkplaceManagementView: View {
    enum Section: String {
        case workplaces = "Workplaces"
        case incentives = "Incentives"
    }

    let section: Section

    @Environment(\.modelContext) private var context
    @Query(sort: \Workplace.name) private var workplaces: [Workplace]
    @Query private var preferences: [WorkplacePaySettings]
    @Query private var rules: [IncentiveRule]
    @Query private var awards: [ManualIncentive]
    @Query private var sessions: [WorkSession]

    @State private var selectedWorkplaceID: UUID?
    @State private var workplaceName = ""
    @State private var mode: PayCalculationMode = .minimumHourly
    @State private var hourly = ""
    @State private var daily = ""
    @State private var nightEnabled = true
    @State private var overtimeEnabled = true
    @State private var ruleName = ""
    @State private var period: IncentivePeriod = .weekly
    @State private var days = 5
    @State private var amount = ""
    @State private var stackable = true
    @State private var manualName = ""
    @State private var manualAmount = ""
    @State private var manualDate = Date()
    @State private var editingRuleID: UUID?
    @State private var editingAwardID: UUID?
    @State private var errorMessage: String?
    @State private var confirmDeleteWorkplace = false

    private var selected: Workplace? { workplaces.first { $0.id == selectedWorkplaceID } }
    private var selectedSettings: WorkplacePaySettings? { preferences.first { $0.workplaceID == selectedWorkplaceID } }
    private var selectedRules: [IncentiveRule] { rules.filter { $0.workplaceID == selectedWorkplaceID } }
    private var selectedAwards: [ManualIncentive] { awards.filter { $0.workplaceID == selectedWorkplaceID } }

    private func decimal(_ text: String) -> Decimal? {
        Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WakSpacing.large) {
                Picker("Workplace", selection: $selectedWorkplaceID) {
                    Text("New workplace").tag(Optional<UUID>.none)
                    ForEach(workplaces) { workplace in
                        Text(workplace.name).tag(Optional(workplace.id))
                    }
                }
                .pickerStyle(.menu)

                if section == .workplaces {
                    workplaceForm
                } else {
                    incentiveForm
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red).font(.footnote)
                }
            }
            .padding(WakSpacing.large)
        }
        .background(CoufunchColor.background)
        .navigationTitle(section.rawValue)
        .onChange(of: selectedWorkplaceID) { _, _ in
            loadWorkplace()
            clearIncentiveEditors()
        }
        .onAppear {
            if selectedWorkplaceID == nil && !workplaces.isEmpty {
                selectedWorkplaceID = workplaces[0].id
            }
            loadWorkplace()
        }
        .alert("Delete Workplace?", isPresented: $confirmDeleteWorkplace) {
            Button("Delete", role: .destructive) { deleteWorkplace() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only a workplace with no work sessions can be deleted. Its settings and incentives will also be removed.")
        }
    }

    private var workplaceForm: some View {
        VStack(alignment: .leading, spacing: WakSpacing.medium) {
            Text(selected == nil ? "Add Workplace" : "Edit Workplace")
                .font(WakTypography.screenTitle)
            TextField("Workplace name", text: $workplaceName)
                .textFieldStyle(.roundedBorder)
            Picker("Pay method", selection: $mode) {
                Text("Minimum hourly wage").tag(PayCalculationMode.minimumHourly)
                Text("Custom hourly wage").tag(PayCalculationMode.customHourly)
                Text("Fixed daily pay").tag(PayCalculationMode.fixedDaily)
            }
            .pickerStyle(.menu)
            if mode == .customHourly {
                TextField("Hourly KRW", text: $hourly)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
            }
            if mode == .fixedDaily {
                TextField("Daily KRW", text: $daily)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
            }
            Toggle("Night premium (22:00–06:00)", isOn: $nightEnabled)
                .disabled(mode == .fixedDaily)
            Toggle("Daily overtime premium (over 8 paid hours)", isOn: $overtimeEnabled)
                .disabled(mode == .fixedDaily)
            Text("These defaults affect new records only. Existing pay snapshots are retained. Weekly overtime is not calculated.")
                .font(.footnote).foregroundStyle(.secondary)
            Button(selected == nil ? "Add Workplace" : "Save Workplace") { saveWorkplace() }
                .buttonStyle(.borderedProminent)
            if selected != nil {
                Button("Add Another Workplace") {
                    selectedWorkplaceID = nil
                    workplaceName = ""
                    mode = .minimumHourly
                    hourly = ""
                    daily = ""
                    nightEnabled = true
                    overtimeEnabled = true
                }
                Button("Delete Workplace", role: .destructive) {
                    confirmDeleteWorkplace = true
                }
                .disabled(sessions.contains { $0.workplaceID == selectedWorkplaceID })
            }
        }
    }

    private var incentiveForm: some View {
        VStack(alignment: .leading, spacing: WakSpacing.large) {
            if selectedWorkplaceID == nil {
                Text("Add a workplace before configuring incentives.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: WakSpacing.medium) {
                    Text("Incentive Rules").font(WakTypography.screenTitle)
                    ForEach(selectedRules) { rule in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(rule.name)
                                Text("\(rule.requiredAttendanceDays.formatted()) days · \(NSDecimalNumber(decimal: rule.amount).intValue.formatted()) KRW")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Edit") { loadRule(rule) }
                            Button(role: .destructive) { remove(rule) } label: {
                                Image(systemName: "trash")
                            }
                        }
                    }
                    TextField("Rule name", text: $ruleName).textFieldStyle(.roundedBorder)
                    Picker("Period", selection: $period) {
                        Text("Daily").tag(IncentivePeriod.daily)
                        Text("Weekly").tag(IncentivePeriod.weekly)
                        Text("Monthly").tag(IncentivePeriod.monthly)
                    }
                    Stepper("Required days: \(days)", value: $days,
                            in: 1...(period == .daily ? 1 : period == .weekly ? 7 : 31))
                    TextField("Bonus KRW", text: $amount)
                        .keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                    Toggle("Stack with other incentives", isOn: $stackable)
                    HStack {
                        Button(editingRuleID == nil ? "Add Rule" : "Save Rule") { saveRule() }
                            .buttonStyle(.borderedProminent)
                        if editingRuleID != nil {
                            Button("Cancel Editing") { clearIncentiveEditors() }
                        }
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: WakSpacing.medium) {
                    Text("Manual Incentives").font(WakTypography.screenTitle)
                    ForEach(selectedAwards) { award in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(award.name)
                                Text("\(NSDecimalNumber(decimal: award.amount).intValue.formatted()) KRW")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Edit") { loadAward(award) }
                            Button(role: .destructive) { remove(award) } label: {
                                Image(systemName: "trash")
                            }
                        }
                    }
                    TextField("Incentive name", text: $manualName).textFieldStyle(.roundedBorder)
                    TextField("Amount KRW", text: $manualAmount)
                        .keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                    DatePicker("Earned on", selection: $manualDate, displayedComponents: .date)
                    HStack {
                        Button(editingAwardID == nil ? "Add Manual Incentive" : "Save Incentive") { saveAward() }
                            .buttonStyle(.borderedProminent)
                        if editingAwardID != nil {
                            Button("Cancel Editing") { clearIncentiveEditors() }
                        }
                    }
                }
            }
        }
        .onChange(of: period) { _, value in
            days = min(days, value == .daily ? 1 : value == .weekly ? 7 : 31)
        }
    }

    private func loadWorkplace() {
        workplaceName = selected?.name ?? ""
        mode = selectedSettings?.payMode ?? .minimumHourly
        hourly = selectedSettings?.customHourlyRate.map { NSDecimalNumber(decimal: $0).stringValue } ?? ""
        daily = selectedSettings?.fixedDailyPay.map { NSDecimalNumber(decimal: $0).stringValue } ?? ""
        nightEnabled = selectedSettings?.nightPremiumEnabled ?? true
        overtimeEnabled = selectedSettings?.overtimePremiumEnabled ?? true
    }

    private func saveWorkplace() {
        let name = workplaceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { errorMessage = "Enter a workplace name."; return }
        let rate = decimal(hourly)
        let wage = decimal(daily)
        if mode == .customHourly && (rate == nil || rate! <= 0) {
            errorMessage = "Enter a valid hourly wage."; return
        }
        if mode == .fixedDaily && (wage == nil || wage! < 0) {
            errorMessage = "Enter a valid daily wage."; return
        }
        let workplace: Workplace
        if let current = selected {
            workplace = current
            current.name = name
        } else {
            workplace = Workplace(name: name)
            context.insert(workplace)
        }
        let values: WorkplacePaySettings
        if let existing = selectedSettings {
            values = existing
        } else {
            values = WorkplacePaySettings(workplaceID: workplace.id, payMode: mode)
            context.insert(values)
        }
        values.payMode = mode
        values.customHourlyRate = mode == .customHourly ? rate : nil
        values.fixedDailyPay = mode == .fixedDaily ? wage : nil
        values.nightPremiumEnabled = mode != .fixedDaily && nightEnabled
        values.overtimePremiumEnabled = mode != .fixedDaily && overtimeEnabled
        commit()
        selectedWorkplaceID = workplace.id
    }

    private func deleteWorkplace() {
        guard let selected, !sessions.contains(where: { $0.workplaceID == selected.id }) else { return }
        preferences.filter { $0.workplaceID == selected.id }.forEach(context.delete)
        rules.filter { $0.workplaceID == selected.id }.forEach(context.delete)
        awards.filter { $0.workplaceID == selected.id }.forEach(context.delete)
        context.delete(selected)
        commit()
        selectedWorkplaceID = workplaces.first { $0.id != selected.id }?.id
    }

    private func saveRule() {
        guard let selectedWorkplaceID,
              !ruleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let value = decimal(amount), value >= 0 else {
            errorMessage = "Enter a valid rule name and bonus."; return
        }
        let rule: IncentiveRule
        if let id = editingRuleID, let existing = rules.first(where: { $0.id == id }) {
            rule = existing
        } else {
            rule = IncentiveRule(workplaceID: selectedWorkplaceID, name: ruleName,
                                 period: period, requiredAttendanceDays: days,
                                 amount: value)
            context.insert(rule)
        }
        rule.name = ruleName
        rule.period = period
        rule.requiredAttendanceDays = days
        rule.amount = value
        rule.canStack = stackable
        commit()
        clearIncentiveEditors()
    }

    private func saveAward() {
        guard let selectedWorkplaceID,
              !manualName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let value = decimal(manualAmount) else {
            errorMessage = "Enter a valid incentive name and amount."; return
        }
        let award: ManualIncentive
        if let id = editingAwardID, let existing = awards.first(where: { $0.id == id }) {
            award = existing
        } else {
            award = ManualIncentive(workplaceID: selectedWorkplaceID,
                                    earnedOn: manualDate, name: manualName, amount: value)
            context.insert(award)
        }
        award.name = manualName
        award.amount = value
        award.earnedOn = manualDate
        commit()
        clearIncentiveEditors()
    }

    private func loadRule(_ rule: IncentiveRule) {
        editingRuleID = rule.id
        ruleName = rule.name
        period = rule.period
        days = rule.requiredAttendanceDays
        amount = NSDecimalNumber(decimal: rule.amount).stringValue
        stackable = rule.canStack
    }

    private func loadAward(_ award: ManualIncentive) {
        editingAwardID = award.id
        manualName = award.name
        manualAmount = NSDecimalNumber(decimal: award.amount).stringValue
        manualDate = award.earnedOn
    }

    private func remove(_ rule: IncentiveRule) {
        context.delete(rule)
        commit()
        if editingRuleID == rule.id { clearIncentiveEditors() }
    }

    private func remove(_ award: ManualIncentive) {
        context.delete(award)
        commit()
        if editingAwardID == award.id { clearIncentiveEditors() }
    }

    private func clearIncentiveEditors() {
        editingRuleID = nil
        editingAwardID = nil
        ruleName = ""
        amount = ""
        manualName = ""
        manualAmount = ""
        manualDate = .now
        stackable = true
    }

    private func commit() {
        do {
            try context.save()
            errorMessage = nil
        } catch {
            context.rollback()
            errorMessage = "Could not save changes."
        }
    }
}

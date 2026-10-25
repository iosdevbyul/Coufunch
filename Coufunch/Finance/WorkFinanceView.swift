import SwiftUI
import SwiftData
import WakTrainerDesignSystem

struct WorkFinanceView: View {
    @StateObject private var holidayStore = KoreanPublicHolidayStore()
    @Environment(\.modelContext) private var modelContext
    @Query private var receivedPay: [ReceivedPayRecord]
    @State private var editingSessionID: UUID?
    @State private var editingAllowanceID: String?
    @State private var allowanceAmount = ""
    @State private var allowanceDepositDate = Date()
    @State private var allowanceError: String?
    @State private var receiptAmount = ""
    @State private var depositDate = Date()
    @State private var bonusInclusion: BonusInclusion = .unknown
    @State private var receiptError: String?
    enum Screen { case pay, strategy }
    let screen: Screen

    @Query private var sessions: [WorkSession]
    @Query private var breaks: [WorkBreak]
    @Query private var workplaces: [Workplace]
    @Query private var settings: [WorkplacePaySettings]
    @Query private var rules: [IncentiveRule]
    @Query private var manual: [ManualIncentive]
    @State private var selectedMonth = Date()
    @State private var simulationWorkplaceID: UUID?
    @State private var simulationDate = Date()

    private var summary: MonthlyPaySummary {
        WorkFinanceSummary.summarize(month: selectedMonth, sessions: sessions,
            breaks: breaks, workplaces: workplaces, settings: settings,
            rules: rules, manual: manual, calendar: .current,
            holidayDates: holidayStore.dates)
    }

    private var estimatedTakeHome: EstimatedTakeHomeResult {
        EstimatedTakeHomeCalculator.calculate(
            gross: summary.total,
            shifts: audit.entries.map { .init(date: $0.start, gross: $0.grossTotal) }
        )
    }

    private var audit: PayrollAuditReport {
        PayrollAuditCalculator.report(month: selectedMonth, sessions: sessions,
            breaks: breaks, workplaces: workplaces, settings: settings, calendar: .current,
            holidayDates: holidayStore.dates)
    }

    private var forecast: PayForecast {
        PayForecastCalculator.calculate(month: selectedMonth, sessions: sessions,
            breaks: breaks, settings: settings, calendar: .current,
            holidayDates: holidayStore.dates)
    }

    private var actualBySession: [UUID: Decimal] {
        var result: [UUID: Decimal] = [:]
        for record in receivedPay.sorted(by: { $0.createdAt < $1.createdAt })
        where record.basis == .net {
            if let id = record.sessionID { result[id] = record.amount }
        }
        return result
    }

    private var legacyReceipts: [ReceivedPayRecord] {
        guard let interval = Calendar.current.dateInterval(of: .month, for: selectedMonth) else { return [] }
        return receivedPay.filter { $0.sessionID == nil && $0.allowanceAwardID == nil && interval.contains($0.monthStart) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// Weekly awards are associated with the last completed shift in the
    /// qualifying week. This is an estimate, not a verified bank payment date.
    private var weeklyBonusGrossBySession: [UUID: Decimal] {
        var result: [UUID: Decimal] = [:]
        for workplace in workplaces {
            var calendar = Calendar.current
            calendar.firstWeekday = workplace.weekStartWeekday
            let awards = WorkIncentiveCalculator.awards(
                sessions: sessions, rules: rules, workplace: workplace, calendar: calendar
            )
            for award in awards {
                // Match the monthly summary's week-end attribution exactly.
                // A bonus assigned to a different month must never be removed
                // from this month's net estimate during reconciliation.
                guard ActualPayReconciliation.weeklyBonusBelongsToMonth(
                    periodStart: award.periodStart, selectedMonth: selectedMonth,
                    calendar: calendar
                ) else { continue }
                guard let rule = rules.first(where: { $0.id == award.ruleID }),
                      rule.period == .weekly,
                      let week = calendar.dateInterval(of: .weekOfYear, for: award.periodStart),
                      let lastShift = sessions.filter({
                          $0.workplaceID == workplace.id && $0.status == .completed &&
                          week.contains($0.startAt)
                      }).max(by: { $0.startAt < $1.startAt }) else { continue }
                result[lastShift.id, default: 0] += award.amount
            }
        }
        return result
    }

    private var weeklyBonusNetBySession: [UUID: Decimal] {
        weeklyBonusGrossBySession.mapValues { gross in
            EstimatedTakeHomeCalculator.calculate(gross: gross, shifts: []).net
        }
    }

    private var bonusInclusionBySession: [UUID: BonusInclusion] {
        var result: [UUID: BonusInclusion] = [:]
        for receipt in receivedPay where receipt.basis == .net {
            if let id = receipt.sessionID { result[id] = receipt.bonusInclusion }
        }
        return result
    }

    private var weeklyAllowanceTimeline: [WeeklyAllowanceTimelineEntry] {
        WeeklyAllowanceTimeline.entries(
            sessions: sessions, workplaces: workplaces, rules: rules,
            receipts: receivedPay, holidays: holidayStore.dates,
            loadedYears: holidayStore.loadedYears, calendar: .current
        ).filter {
            Calendar.current.isDate($0.earnedAt, equalTo: selectedMonth, toGranularity: .month)
        }
    }

    private var reconciledNet: Decimal {
        let reconciled = ActualPayReconciliation.total(
            estimatedMonthlyNet: estimatedTakeHome.net,
            shiftGross: audit.entries.map { (id: $0.id, gross: $0.grossTotal) },
            actualBySession: actualBySession,
            bonusNetBySession: weeklyBonusNetBySession,
            bonusInclusionBySession: bonusInclusionBySession
        )
        // A separate deposit replaces the estimated net allowance; it is not
        // added on top of the existing monthly estimate.
        return weeklyAllowanceTimeline.reduce(reconciled) { sum, item in
            guard let actual = item.separatelyReceivedNet,
                  item.inclusion != .included else { return sum }
            let estimated = EstimatedTakeHomeCalculator.calculate(
                gross: item.amount, shifts: []).net
            return sum - estimated + actual
        }
    }

    private var simulationResult: WorkdaySimulationResult? {
        guard let workplace = workplaces.first(where: { $0.id == simulationWorkplaceID }) else {
            return nil
        }
        return WorkdayIncentiveSimulator.simulate(
            candidateDate: simulationDate, workplace: workplace,
            sessions: sessions, rules: rules, calendar: .current
        )
    }

    private var opportunities: [NextWorkdayOpportunity] {
        WorkFinanceSummary.opportunities(on: Date(), sessions: sessions,
                                         workplaces: workplaces, rules: rules, calendar: .current)
    }

    private func money(_ amount: Decimal) -> String {
        NSDecimalNumber(decimal: amount).intValue.formatted(.currency(code: "KRW"))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WakSpacing.large) {
                if screen == .pay && !holidayStore.loadedYears.contains(Calendar.current.component(.year, from: selectedMonth)) {
                    Text("Public holiday data is unavailable. Holiday premiums may be missing.")
                        .font(.footnote).foregroundStyle(.orange)
                }
                if screen == .pay {
                    HStack {
                        Button { selectedMonth = Calendar.current.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth } label: {
                            Image(systemName: "chevron.left")
                        }
                        Spacer()
                        Text(selectedMonth, format: .dateTime.year().month()).font(.headline)
                        Spacer()
                        Button { selectedMonth = Calendar.current.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth } label: {
                            Image(systemName: "chevron.right")
                        }
                    }
                    CoufunchCard {
                        VStack(alignment: .leading, spacing: WakSpacing.medium) {
                            Text("Estimated Gross Pay").font(WakTypography.screenTitle)
                            Text(money(summary.total)).font(.title.bold()).foregroundStyle(CoufunchColor.primary)
                            Divider()
                            Text("Estimated / Actual Take-Home Pay").font(WakTypography.screenTitle)
                            Text(money(reconciledNet))
                                .font(.title2.bold())
                            row("Estimated insurance deductions", money(estimatedTakeHome.deductions))
                            Text("Entered actual deposits replace estimates for those shifts; other shifts remain estimated.")
                                .font(.caption).foregroundStyle(.secondary)
                            Text("Estimated using the 2026 employee social insurance rate (9.717383%). Actual deductions, tax, and eligibility may differ.")
                                .font(.caption).foregroundStyle(.secondary)
                            row("Completed days", "\(summary.completedDays)")
                            row("Base pay", money(summary.basePay))
                            row("Night premium", money(summary.nightPremium))
                            row("Overtime premium", money(summary.overtimePremium))
                            row("Holiday premium", money(summary.holidayPremium))
                            row("Automatic incentives", money(summary.automaticIncentives))
                            row("Manual incentives", money(summary.manualIncentives))
                            row("Average per completed day", money(summary.dailyAverage))
                            if summary.skippedSessions > 0 {
                                Text(String(format: String(localized: "%d incomplete pay record(s) excluded."), summary.skippedSessions))
                                    .font(.footnote).foregroundStyle(.orange)
                            }
                        }
                    }
                    CoufunchCard {
                        VStack(alignment: .leading, spacing: WakSpacing.medium) {
                            Text("Payroll Audit").font(WakTypography.screenTitle)
                            ShareLink(item: PayrollAuditCSV.make(report: audit, calendar: .current)) {
                                Label("Share Payroll CSV", systemImage: "square.and.arrow.up")
                            }
                            .disabled(audit.entries.isEmpty)
                            Text("Shares a CSV text breakdown outside this app only when you choose. It may contain workplace and shift details.")
                                .font(.caption).foregroundStyle(.secondary)
                            Text("Completed shifts only. Compare these gross estimates with a gross payslip; bonuses and deductions are shown separately in the monthly summary.")
                                .font(.footnote).foregroundStyle(.secondary)
                            if audit.entries.isEmpty {
                                Text("No completed shift breakdowns for this month.")
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(audit.entries) { item in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(item.workplaceName).font(.headline)
                                    Text(item.start, format: .dateTime.month().day().hour().minute())
                                        .font(.caption).foregroundStyle(.secondary)
                                    row("Paid minutes", "\(item.paidMinutes)")
                                    row("Night minutes", "\(item.nightMinutes)")
                                    row("Daily overtime minutes", "\(item.dailyOvertimeMinutes)")
                                    row("Base pay", money(item.basePay))
                                    row("Night premium", money(item.nightPremium))
                                    row("Overtime premium", money(item.overtimePremium))
                                    row("Holiday premium", money(item.holidayPremium))
                                    row("Shift gross", money(item.grossTotal))
                                    if let actual = actualBySession[item.id] {
                                        row("Actual received", money(actual))
                                        if let date = receivedPay.first(where: { $0.sessionID == item.id })?.depositedAt {
                                            HStack {
                                                Text("Deposit date").foregroundStyle(.secondary)
                                                Spacer()
                                                Text(date, format: .dateTime.year().month().day())
                                            }
                                            .font(.subheadline)
                                        }
                                    }
                                    Button(actualBySession[item.id] == nil ? "Enter Actual Pay" : "Edit Actual Pay") {
                                        editingSessionID = item.id
                                        receiptAmount = actualBySession[item.id].map {
                                            NSDecimalNumber(decimal: $0).stringValue
                                        } ?? ""
                                        receiptError = nil
                                        bonusInclusion = bonusInclusionBySession[item.id] ?? .unknown
                                        depositDate = receivedPay.first(where: { $0.sessionID == item.id })?.depositedAt ?? Date()
                                    }
                                    .buttonStyle(.bordered)
                                    Divider()
                                }
                            }
                            row("Total shift gross", money(audit.shiftGross))
                            if audit.excluded > 0 {
                                Text(String(format: String(localized: "%d completed shift(s) could not be calculated."), audit.excluded))
                                    .font(.caption).foregroundStyle(.orange)
                            }
                        }
                    }

                    CoufunchCard {
                        VStack(alignment: .leading, spacing: WakSpacing.medium) {
                            Text("Shift Pay Forecast").font(WakTypography.screenTitle)
                            row("Completed shifts", "\(forecast.completedCount)")
                            row("Completed shift pay", money(forecast.completedGross))
                            row("Confirmed shifts", "\(forecast.confirmedCount)")
                            row("Confirmed projected pay", money(forecast.confirmedGross))
                            row("Applied shifts", "\(forecast.appliedCount)")
                            row("Applied hypothetical pay", money(forecast.appliedGross))
                            row("Completed + confirmed shifts", money(forecast.securedGross))
                            row("Including applications (hypothetical)", money(forecast.possibleGross))
                            if forecast.unpricedCount > 0 {
                                Text(String(format: String(localized: "%d shift(s) without sufficient pay data."), forecast.unpricedCount))
                                    .font(.caption).foregroundStyle(.orange)
                            }
                        }
                    }

                    if !weeklyAllowanceTimeline.isEmpty {
                        CoufunchCard {
                            VStack(alignment: .leading, spacing: WakSpacing.medium) {
                                Text("Weekly Allowance Timeline").font(WakTypography.screenTitle)
                                Text("Earned date and actual deposit date are separate. Six-day special allowances are expected the following Tuesday.")
                                    .font(.caption).foregroundStyle(.secondary)
                                ForEach(weeklyAllowanceTimeline) { item in
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(item.workplaceName).font(.headline)
                                        row("Estimated weekly allowance (gross)", money(item.amount))
                                        HStack {
                                            Text("Allowance earned").foregroundStyle(.secondary)
                                            Spacer()
                                            Text(item.earnedAt, format: .dateTime.year().month().day())
                                        }
                                        .font(.subheadline)
                                        if let separate = item.separatelyReceivedNet {
                                            row("Separately received allowance (net)", money(separate))
                                        }
                                        if let expected = item.expectedPaymentAt {
                                            HStack {
                                                Text("Expected special allowance payday").foregroundStyle(.secondary)
                                                Spacer()
                                                Text(expected, format: .dateTime.year().month().day())
                                            }
                                            .font(.subheadline)
                                        }
                                        if let deposited = item.actualDepositAt {
                                            HStack {
                                                Text("Confirmed included deposit date").foregroundStyle(.secondary)
                                                Spacer()
                                                Text(deposited, format: .dateTime.year().month().day())
                                            }
                                            .font(.subheadline)
                                        } else {
                                            Text(item.inclusion == .excluded
                                                 ? "Allowance marked as separately paid; deposit not yet recorded."
                                                 : "Allowance deposit date is unconfirmed.")
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                        Button(item.separatelyReceivedNet == nil ? "Record Separate Allowance" : "Edit Separate Allowance") {
                                            editingAllowanceID = item.id
                                            allowanceAmount = item.separatelyReceivedNet.map { NSDecimalNumber(decimal: $0).stringValue } ?? ""
                                            allowanceDepositDate = receivedPay.first(where: { $0.allowanceAwardID == item.id })?.depositedAt ?? Date()
                                            allowanceError = nil
                                        }
                                        .buttonStyle(.bordered)
                                        .disabled(item.inclusion == .included)
                                    }
                                    Divider()
                                }
                            }
                        }
                    }

                    if !legacyReceipts.isEmpty {
                        CoufunchCard {
                            VStack(alignment: .leading, spacing: WakSpacing.medium) {
                                Text("Previous Payment Records").font(WakTypography.screenTitle)
                                Text("Older monthly payment records are preserved for reference and are not counted again in the shift-based total.")
                                    .font(.caption).foregroundStyle(.secondary)
                                ForEach(legacyReceipts) { receipt in
                                    HStack {
                                        Text(receipt.monthStart, format: .dateTime.year().month())
                                        Spacer()
                                        Text(money(receipt.amount))
                                        Text(receipt.basis == .net ? "Net" : "Gross")
                                            .foregroundStyle(.secondary)
                                    }
                                    if !receipt.note.isEmpty {
                                        Text(receipt.note).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }

                    Text("Estimates exclude tax and insurance deductions. Weekly bonuses are attributed to the week-end date.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text("Next Incentive Goals")
                        .font(WakTypography.screenTitle)
                    if opportunities.isEmpty {
                        Text("No pending incentive goals for the current periods.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(opportunities) { goal in
                        CoufunchCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(goal.workplaceName).foregroundStyle(.secondary)
                                Text(goal.ruleName).font(.headline)
                                row("More workdays needed", "\(goal.remainingDays)")
                                row("Potential bonus", money(goal.amount))
                                Text("Deadline: \(goal.periodEnd.addingTimeInterval(-1), format: .dateTime.month().day())")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    CoufunchCard {
                        VStack(alignment: .leading, spacing: WakSpacing.medium) {
                            Text("What If I Work One More Day?")
                                .font(WakTypography.screenTitle)
                            Picker("Workplace", selection: $simulationWorkplaceID) {
                                Text("Choose a workplace").tag(Optional<UUID>.none)
                                ForEach(workplaces) { workplace in
                                    Text(workplace.name).tag(Optional(workplace.id))
                                }
                            }
                            .pickerStyle(.menu)
                            DatePicker("Additional workday", selection: $simulationDate,
                                       displayedComponents: .date)
                            if let simulationResult {
                                if simulationResult.alreadyCompletedOnDate {
                                    Text("This workplace already has a completed attendance record on this date. An additional shift will not increase the attendance day count.")
                                        .font(.footnote).foregroundStyle(.secondary)
                                } else {
                                    row("New bonus unlocked", money(simulationResult.newlyUnlockedBonus))
                                    if simulationResult.triggeredRules.isEmpty {
                                        Text("This extra attendance day does not immediately unlock a bonus.")
                                            .font(.footnote).foregroundStyle(.secondary)
                                    } else {
                                        ForEach(simulationResult.triggeredRules, id: \.self) { name in
                                            Label(name, systemImage: "checkmark.circle")
                                                .font(.footnote)
                                        }
                                    }
                                }
                            } else {
                                Text("Select a workplace to simulate the incentive impact.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            Text("Simulation only: no work record is saved. This assumes the selected date becomes a completed attendance day. Daily wages, approvals, and deductions are excluded.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }

                    Text("These opportunities depend on approval and qualifying completed workdays. Daily wages are not included in the potential bonus.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(WakSpacing.large)
        }
        .background(CoufunchColor.background)
        .navigationTitle(LocalizedStringKey(screen == .pay ? "Pay & Allowances" : "Work Strategy"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: Binding(
            get: { editingSessionID != nil },
            set: { if !$0 { editingSessionID = nil } }
        )) {
            NavigationStack {
                Form {
                    TextField("Actual received (KRW)", text: $receiptAmount)
                        .keyboardType(.numberPad)
                    DatePicker("Bank deposit date", selection: $depositDate, displayedComponents: .date)
                    Text("The deposit date is recorded separately from the work date and does not change which month earned pay belongs to.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let id = editingSessionID,
                       let bonus = weeklyBonusGrossBySession[id], bonus > 0 {
                        Section {
                            Text("A weekly allowance is estimated for this workweek. Does the entered deposit include it?")
                            Picker("Weekly allowance included?", selection: $bonusInclusion) {
                                Text("Yes, included").tag(BonusInclusion.included)
                                Text("No, paid separately").tag(BonusInclusion.excluded)
                                Text("Not sure yet").tag(BonusInclusion.unknown)
                            }
                            .pickerStyle(.inline)
                            if bonusInclusion == .unknown {
                                Text("Bonus inclusion is unconfirmed. The estimated allowance remains in the total until confirmed.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if let receiptError {
                        Text(LocalizedStringKey(receiptError)).foregroundStyle(.red)
                    }
                    if editingSessionID.flatMap({ actualBySession[$0] }) != nil {
                        Button("Remove Actual Pay", role: .destructive) { clearActual() }
                    }
                }
                .navigationTitle("Actual Received Pay")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { editingSessionID = nil }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Save") { saveActual() }
                    }
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { editingAllowanceID != nil },
            set: { if !$0 { editingAllowanceID = nil } }
        )) {
            NavigationStack {
                Form {
                    TextField("Separate allowance received (KRW)", text: $allowanceAmount)
                        .keyboardType(.numberPad)
                    DatePicker("Bank deposit date", selection: $allowanceDepositDate,
                               displayedComponents: .date)
                    Text("Enter the net amount actually deposited separately. This replaces the estimated net allowance in its earned month.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let allowanceError {
                        Text(LocalizedStringKey(allowanceError)).foregroundStyle(.red)
                    }
                    if let id = editingAllowanceID,
                       receivedPay.contains(where: { $0.allowanceAwardID == id }) {
                        Button("Remove Separate Allowance", role: .destructive) {
                            removeSeparateAllowance()
                        }
                    }
                }
                .navigationTitle("Separate Weekly Allowance")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { editingAllowanceID = nil }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Save") { saveSeparateAllowance() }
                    }
                }
            }
        }
        .onAppear { simulationWorkplaceID = simulationWorkplaceID ?? workplaces.first?.id }
        .task(id: Calendar.current.component(.year, from: selectedMonth)) {
            let year = Calendar.current.component(.year, from: selectedMonth)
            await holidayStore.load(year: year)
            await holidayStore.load(year: year + 1)
        }
    }

    private func saveActual() {
        guard let id = editingSessionID,
              let amount = Decimal(string: receiptAmount, locale: Locale(identifier: "en_US_POSIX")),
              amount >= 0,
              let entry = audit.entries.first(where: { $0.id == id }),
              let month = Calendar.current.dateInterval(of: .month, for: entry.start)?.start else {
            receiptError = "Enter a valid non-negative payment amount."
            return
        }
        let existing = receivedPay.filter { $0.sessionID == id }
        if let first = existing.first {
            first.amount = amount
            first.basis = .net
            first.bonusInclusion = bonusInclusion
            first.depositedAt = depositDate
            for duplicate in existing.dropFirst() { modelContext.delete(duplicate) }
        } else {
            modelContext.insert(ReceivedPayRecord(monthStart: month, amount: amount,
                                                   basis: .net, sessionID: id,
                                                   bonusInclusion: bonusInclusion,
                                                   depositedAt: depositDate))
        }
        do {
            try modelContext.save()
            editingSessionID = nil
            receiptError = nil
        } catch {
            modelContext.rollback()
            receiptError = "Unable to save the payment record."
        }
    }

    private func clearActual() {
        guard let id = editingSessionID else { return }
        for record in receivedPay where record.sessionID == id { modelContext.delete(record) }
        do {
            try modelContext.save()
            editingSessionID = nil
            receiptError = nil
        } catch {
            modelContext.rollback()
            receiptError = "Unable to delete the payment record."
        }
    }

    private func saveSeparateAllowance() {
        guard let id = editingAllowanceID,
              let item = weeklyAllowanceTimeline.first(where: { $0.id == id }),
              item.inclusion != .included,
              let amount = Decimal(string: allowanceAmount, locale: Locale(identifier: "en_US_POSIX")),
              amount >= 0,
              let month = Calendar.current.dateInterval(of: .month, for: item.earnedAt)?.start else {
            allowanceError = "Enter a valid amount. Allowance already included in a shift cannot be recorded separately."
            return
        }
        let existing = receivedPay.filter { $0.allowanceAwardID == id }
        if let first = existing.first {
            first.amount = amount
            first.depositedAt = allowanceDepositDate
            first.basis = .net
            for duplicate in existing.dropFirst() { modelContext.delete(duplicate) }
        } else {
            modelContext.insert(ReceivedPayRecord(
                monthStart: month, amount: amount, basis: .net,
                depositedAt: allowanceDepositDate, allowanceAwardID: id))
        }
        do {
            try modelContext.save()
            editingAllowanceID = nil
            allowanceError = nil
        } catch {
            modelContext.rollback()
            allowanceError = "Unable to save the payment record."
        }
    }

    private func removeSeparateAllowance() {
        guard let id = editingAllowanceID else { return }
        for record in receivedPay where record.allowanceAwardID == id {
            modelContext.delete(record)
        }
        do {
            try modelContext.save()
            editingAllowanceID = nil
            allowanceError = nil
        } catch {
            modelContext.rollback()
            allowanceError = "Unable to delete the payment record."
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(LocalizedStringKey(title)).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.semibold)
        }
        .font(.subheadline)
    }
}

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
    @State private var payrollDetailMode: PayrollDetailMode = .list
    @State private var selectedPayrollDay = Date()

    private enum PayrollDetailMode: String, CaseIterable {
        case list, calendar
    }

    private var visibleAuditEntries: [PayrollAuditEntry] {
        payrollDetailMode == .list ? audit.entries : audit.entries.filter {
            Calendar.current.isDate($0.start, inSameDayAs: selectedPayrollDay)
        }
    }

    private struct EarnedIncentive: Identifiable {
        let id: String
        let day: Date
        let name: String
        let amount: Decimal
    }

    // Present awards on the qualifying attendance date; keep the existing
    // month-end attribution in WorkFinanceSummary untouched.
    private var earnedIncentives: [EarnedIncentive] {
        var result: [EarnedIncentive] = []
        let calendar = Calendar.current
        for workplace in workplaces {
            var workCalendar = calendar
            workCalendar.firstWeekday = workplace.weekStartWeekday
            let completedDates = Array(Set(sessions.filter {
                $0.workplaceID == workplace.id && $0.status == .completed
            }.map { workCalendar.startOfDay(for: $0.startAt) })).sorted()
            for award in WorkIncentiveCalculator.awards(
                sessions: sessions, rules: rules, workplace: workplace, calendar: workCalendar
            ) {
                guard let rule = rules.first(where: { $0.id == award.ruleID }) else { continue }
                let component: Calendar.Component = rule.period == .weekly ? .weekOfYear :
                    rule.period == .monthly ? .month : .day
                guard let period = workCalendar.dateInterval(of: component, for: award.periodStart) else { continue }
                let qualifyingDays = completedDates.filter { period.contains($0) }
                guard qualifyingDays.count >= rule.requiredAttendanceDays else { continue }
                let day = qualifyingDays[rule.requiredAttendanceDays - 1]
                guard calendar.isDate(day, equalTo: selectedMonth, toGranularity: .month) else { continue }
                result.append(EarnedIncentive(
                    id: "\(workplace.id)-\(award.ruleID)-\(award.periodStart.timeIntervalSince1970)",
                    day: day, name: rule.name, amount: award.amount))
            }
        }
        for bonus in manual where calendar.isDate(bonus.earnedOn, equalTo: selectedMonth, toGranularity: .month) {
            result.append(EarnedIncentive(id: "manual-\(bonus.id)", day: bonus.earnedOn,
                                          name: bonus.name, amount: bonus.amount))
        }
        return result
    }

    private func incentiveTotal(on day: Date) -> Decimal {
        earnedIncentives.filter { Calendar.current.isDate($0.day, inSameDayAs: day) }
            .reduce(Decimal.zero) { $0 + $1.amount }
    }

    private func shiftGross(on day: Date) -> Decimal {
        audit.entries.filter { Calendar.current.isDate($0.start, inSameDayAs: day) }
            .reduce(Decimal.zero) { $0 + $1.grossTotal }
    }

    private var selectedDayGross: Decimal {
        shiftGross(on: selectedPayrollDay) + incentiveTotal(on: selectedPayrollDay)
    }

    private var selectedDayNet: Decimal {
        EstimatedTakeHomeCalculator.calculate(gross: selectedDayGross, shifts: []).net
    }

    private var payrollCalendar: some View {
        let calendar = Calendar.current
        let interval = calendar.dateInterval(of: .month, for: selectedMonth)
        let start = interval?.start ?? calendar.startOfDay(for: selectedMonth)
        let dayCount = calendar.range(of: .day, in: .month, for: start)?.count ?? 30
        let firstOffset = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
        return VStack(spacing: 8) {
            HStack {
                ForEach(0..<7, id: \.self) { weekday in
                    let value = (weekday + calendar.firstWeekday - 1) % 7 + 1
                    Text(calendar.shortStandaloneWeekdaySymbols[value - 1])
                        .font(.caption2)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(.secondary)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 7), spacing: 7) {
                ForEach(0..<(firstOffset + dayCount), id: \.self) { index in
                    if index < firstOffset {
                        Color.clear.frame(height: 44)
                    } else {
                        let day = calendar.date(byAdding: .day, value: index - firstOffset, to: start) ?? start
                        let worked = audit.entries.contains { calendar.isDate($0.start, inSameDayAs: day) }
                        let bonus = incentiveTotal(on: day) > 0
                        let selected = calendar.isDate(day, inSameDayAs: selectedPayrollDay)
                        Button {
                            selectedPayrollDay = day
                        } label: {
                            VStack(spacing: 3) {
                                Text("\(calendar.component(.day, from: day))")
                                    .font(.subheadline.weight(selected ? .bold : .regular))
                                HStack(spacing: 3) {
                                    if worked { Circle().fill(CoufunchColor.primary).frame(width: 5, height: 5) }
                                    if bonus { Circle().fill(.orange).frame(width: 5, height: 5) }
                                }
                                .frame(height: 6)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(selected ? CoufunchColor.primary.opacity(0.15) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(day, format: .dateTime.year().month().day()))
                        .accessibilityValue(worked ? "Worked day" : bonus ? "Incentive earned" : "")
                    }
                }
            }
            HStack(spacing: 12) {
                Label("Worked", systemImage: "circle.fill").foregroundStyle(CoufunchColor.primary)
                Label("Incentive earned", systemImage: "circle.fill").foregroundStyle(.orange)
                Spacer()
            }
            .font(.caption)
        }
    }

    private struct MonthlyBonusRow: Identifiable {
        let id: String
        let workplaceName: String
        let ruleName: String
        let earnedAt: Date
        let amount: Decimal
    }

    private var monthlyBonuses: [MonthlyBonusRow] {
        var rows: [MonthlyBonusRow] = []
        for workplace in workplaces {
            let awards = WorkIncentiveCalculator.awards(
                sessions: sessions, rules: rules, workplace: workplace, calendar: .current)
            for award in awards {
                guard let rule = rules.first(where: { $0.id == award.ruleID }),
                      rule.period == .monthly,
                      Calendar.current.isDate(award.periodStart, equalTo: selectedMonth, toGranularity: .month) else { continue }
                rows.append(MonthlyBonusRow(
                    id: "\(workplace.id)-\(award.ruleID)-\(award.periodStart.timeIntervalSince1970)",
                    workplaceName: workplace.name, ruleName: rule.name,
                    earnedAt: award.periodStart, amount: award.amount))
            }
        }
        return rows.sorted { $0.earnedAt > $1.earnedAt }
    }
    @State private var confirmationKeyLoaded: String?
    @State private var confirmedFullMonth = false
    @State private var simulationWorkplaceID: UUID?
    @State private var simulationDate = Date()

    private var summary: MonthlyPaySummary {
        WorkFinanceSummary.summarize(month: selectedMonth, sessions: sessions,
            breaks: breaks, workplaces: workplaces, settings: settings,
            rules: rules, manual: manual, calendar: .current,
            holidayDates: holidayStore.dates)
    }

    private struct WorkplaceHealthScreening: Identifiable {
        let id: UUID
        let workplaceName: String
        let result: MonthlyHealthEligibilityResult
    }

    private var healthEligibilityPreview: [WorkplaceHealthScreening] {
        return workplaces.map { workplace in
            let result = MonthlyHealthEligibilityScreening.evaluate(
                month: selectedMonth,
                workplaceID: workplace.id,
                sessions: sessions,
                employedPreviousMonth: EmploymentContextStore.previousMonthEmployment(
                    workplaceID: workplace.id, month: selectedMonth, calendar: .current
                ),
                startedOnFirstDay: EmploymentContextStore.startedOnFirstDay(
                    workplaceID: workplace.id, month: selectedMonth, calendar: .current
                ),
                calendar: .current
            )
            return WorkplaceHealthScreening(id: workplace.id, workplaceName: workplace.name, result: result)
        }
    }

    private var insurancePreview: DailyWorkerInsuranceBreakdown? {
        // A combined payroll amount cannot be allocated to separate employers.
        guard workplaces.count == 1, let workplace = workplaces.first else { return nil }
        return DailyWorkerInsuranceEstimator.estimate(
            gross: summary.total,
            pensionEnrollment: MonthlyInsuranceProfileStore.enrollment(
                workplaceID: workplace.id, month: selectedMonth,
                field: .pensionEnrollment, calendar: .current
            ),
            healthEnrollment: MonthlyInsuranceProfileStore.enrollment(
                workplaceID: workplace.id, month: selectedMonth,
                field: .healthEnrollment, calendar: .current
            ),
            pensionBase: MonthlyInsuranceProfileStore.contributionBase(
                workplaceID: workplace.id, month: selectedMonth,
                field: .pensionBase, calendar: .current
            ),
            healthBase: MonthlyInsuranceProfileStore.contributionBase(
                workplaceID: workplace.id, month: selectedMonth,
                field: .healthBase, calendar: .current
            )
        )
    }

    private var insuranceComparison: InsuranceEstimateComparison? {
        guard let insurancePreview else { return nil }
        return InsuranceEstimateComparison.calculate(
            gross: summary.total, profile: insurancePreview
        )
    }

    private var currentConfirmationKey: String? {
        guard workplaces.count == 1, let workplace = workplaces.first else { return nil }
        return "payroll.validation.\(workplace.id.uuidString).\(EmploymentContextStore.monthKey(selectedMonth, calendar: .current)).fullMonthConfirmed"
    }

    private var receiptEstimateValidation: MonthlyReceiptEstimateValidation? {
        guard workplaces.count == 1, let workplace = workplaces.first else { return nil }
        return MonthlyReceiptEstimateValidation.calculate(
            month: selectedMonth,
            workplaceID: workplace.id,
            receipts: receivedPay,
            gross: summary.total,
            hasIncentives: summary.automaticIncentives != 0 || summary.manualIncentives != 0,
            fullMonthConfirmed: confirmationKeyLoaded == currentConfirmationKey && confirmedFullMonth,
            profileNet: insurancePreview?.estimatedNet,
            calendar: .current
        )
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
                                .font(.title.bold())
                            row("Estimated insurance deductions", money(estimatedTakeHome.deductions))
                            Divider()
                            if let key = currentConfirmationKey {
                                Toggle("I confirm this receipt covers the entire month", isOn: Binding(
                                    get: { confirmationKeyLoaded == key && confirmedFullMonth },
                                    set: { confirmed in
                                        confirmationKeyLoaded = key
                                        confirmedFullMonth = confirmed
                                        UserDefaults.standard.set(confirmed, forKey: key)
                                    }
                                ))
                                .font(.footnote)
                            }
                            if let validation = receiptEstimateValidation {
                                Divider()
                                Text("Monthly Receipt Accuracy Check").font(.headline)
                                row("Confirmed Monthly Net Receipt", money(validation.actualNet))
                                row("Flat-Rate Estimate Error", money(validation.flatRateError))
                                if let profileError = validation.profileError {
                                    row("Insurance Profile Estimate Error", money(profileError))
                                } else {
                                    row("Insurance Profile Estimate Error", "Unknown")
                                }
                                Text("Estimate minus actual deposit. Positive values mean the estimate is too high. Only one full-month net receipt with matching workplace and bonus coverage can be compared.")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text("Income tax is not included in either estimate. This check does not alter recorded deposits or reconciliation.")
                                    .font(.caption).foregroundStyle(.secondary)
                            } else {
                                Text("Monthly accuracy check unavailable: record one complete monthly net receipt for a single workplace, including any bonuses, without separate shift or allowance receipts.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Divider()
                            Text("Insurance Profile Preview").font(.headline)
                            ForEach(healthEligibilityPreview) { item in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.workplaceName).font(.subheadline.bold())
                                    HStack {
                                        Text("Health Eligibility Screening")
                                        Spacer()
                                        Text("\(item.result.attendanceDays) days")
                                    }
                                    Text(item.result.screening == .enrolled ? "Likely eligible" :
                                         item.result.screening == .notEnrolled ? "Not eligible by screening" : "Needs confirmation")
                                        .foregroundStyle(.secondary)
                                }
                                .font(.caption)
                            }
                            Text("Employment answers are stored by workplace and month. Confirm actual insurance enrollment with the employer.")
                                .font(.caption).foregroundStyle(.secondary)
                            if let insurancePreview {
                                row("Employment Insurance", money(insurancePreview.employment))
                                if let pension = insurancePreview.pension {
                                    row("National Pension", money(pension))
                                }
                                if let health = insurancePreview.health,
                                   let care = insurancePreview.longTermCare {
                                    row("Health Insurance", money(health))
                                    row("Long-Term Care Insurance", money(care))
                                }
                                if insurancePreview.pension == nil || insurancePreview.health == nil {
                                    Text("Pension or health premiums require confirmed enrollment and contribution bases in Settings.")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                if let comparison = insuranceComparison,
                                   let difference = comparison.deductionDifference {
                                    row("Difference from Flat-Rate Deductions", money(difference))
                                    Text("Positive amounts mean the profile estimate deducts more than the existing flat-rate estimate. This comparison does not alter recorded payments.")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                if let net = insurancePreview.estimatedNet {
                                    row("Profile-Based Estimated Net", money(net))
                                } else {
                                    Text("Profile-based net estimate unavailable: confirm enrollment and contribution bases in Settings.")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            } else {
                                Text("A combined insurance estimate is unavailable for multiple workplaces. Review each workplace's monthly insurance profile separately.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Text("Preview only. No income tax included. Recorded deposits and existing reconciliation are unchanged.")
                                .font(.caption).foregroundStyle(.secondary)
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
                            HStack {
                                Text("Payroll Audit").font(WakTypography.screenTitle)
                                Spacer()
                                Picker("Detail display", selection: $payrollDetailMode) {
                                    Image(systemName: "list.bullet").tag(PayrollDetailMode.list)
                                    Image(systemName: "calendar").tag(PayrollDetailMode.calendar)
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 120)
                                .accessibilityLabel("Payroll detail display mode")
                            }
                            if payrollDetailMode == .calendar {
                                payrollCalendar
                                row("Selected day gross (including incentives)", money(selectedDayGross))
                                row("Selected day estimated net (including incentives)", money(selectedDayNet))
                                Text("The net amount is a flat-rate estimate, not a confirmed deposit. Incentives appear on the day their attendance threshold is reached.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
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
                            if visibleAuditEntries.isEmpty && !audit.entries.isEmpty {
                                Text("No completed shifts on the selected date.")
                                    .foregroundStyle(.secondary)
                            }
                            if payrollDetailMode == .calendar {
                                ForEach(earnedIncentives.filter { Calendar.current.isDate($0.day, inSameDayAs: selectedPayrollDay) }) { bonus in
                                    row(bonus.name, money(bonus.amount))
                                }
                            }
                            ForEach(visibleAuditEntries) { item in
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
                                    row("Shift estimated net", money(EstimatedTakeHomeCalculator.calculate(gross: item.grossTotal, shifts: []).net))
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

                            if audit.excluded > 0 {
                                Text(String(format: String(localized: "%d completed shift(s) could not be calculated."), audit.excluded))
                                    .font(.caption).foregroundStyle(.orange)
                            }
                        }
                    }

                    if !weeklyAllowanceTimeline.isEmpty || !monthlyBonuses.isEmpty {
                        CoufunchCard {
                            VStack(alignment: .leading, spacing: WakSpacing.medium) {
                                Text("Allowance & Incentive Payment Details").font(WakTypography.screenTitle)
                                Text("Weekly allowances and monthly incentives are listed by their earned period. Payment dates are shown only when verified.")
                                    .font(.caption).foregroundStyle(.secondary)
                                ForEach(monthlyBonuses) { bonus in
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(bonus.workplaceName).font(.headline)
                                        row(bonus.ruleName, money(bonus.amount))
                                        Text(bonus.earnedAt, format: .dateTime.year().month())
                                            .font(.caption).foregroundStyle(.secondary)
                                        Text("Monthly incentive deposit date is not confirmed.")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Divider()
                                }
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
        .onAppear {
            simulationWorkplaceID = simulationWorkplaceID ?? workplaces.first?.id
            loadReceiptConfirmation()
        }
        .onChange(of: selectedMonth) { _, date in
            selectedPayrollDay = Calendar.current.dateInterval(of: .month, for: date)?.start ?? date
            loadReceiptConfirmation()
        }
        .onChange(of: workplaces.map(\.id)) { _, _ in loadReceiptConfirmation() }
        .task(id: Calendar.current.component(.year, from: selectedMonth)) {
            let year = Calendar.current.component(.year, from: selectedMonth)
            await holidayStore.load(year: year)
            await holidayStore.load(year: year + 1)
        }
    }

    private func loadReceiptConfirmation() {
        confirmationKeyLoaded = currentConfirmationKey
        confirmedFullMonth = currentConfirmationKey.map {
            UserDefaults.standard.bool(forKey: $0)
        } ?? false
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

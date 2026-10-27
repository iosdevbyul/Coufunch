import SwiftUI
import UIKit
import SwiftData
import WakTrainerDesignSystem

struct WorkFinanceView: View {
    @StateObject private var holidayStore = KoreanPublicHolidayStore()
    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var appLocale
    @Query private var receivedPay: [ReceivedPayRecord]
    @State private var editingSessionID: UUID?
    @State private var receiptAmount = ""
    @State private var receiptGrossAmount = ""
    @State private var depositDate = Date()
    @State private var bonusInclusion: BonusInclusion = .unknown
    @State private var receiptIncludedTypes: Set<String> = []
    @State private var showPayrollExportOptions = false
    @State private var payrollCSVAttachment: PayrollCSVAttachment?
    @State private var payrollCSVError: String?
    @State private var receiptError: String?
    @State private var scenarioAdditionalShifts = 0
    @State private var scenarioGrossPerShift = ""
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

    // Attach one day's incentive awards to the last completed shift only.
    private func assignedIncentives(for item: PayrollAuditEntry) -> [EarnedIncentive] {
        let lastShift = audit.entries.filter {
            Calendar.current.isDate($0.start, inSameDayAs: item.start)
        }.last
        guard lastShift?.id == item.id else { return [] }
        return earnedIncentives.filter {
            Calendar.current.isDate($0.day, inSameDayAs: item.start)
        }
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

    private var statusForecast: PayForecast {
        PayForecastCalculator.calculate(
            month: selectedMonth,
            sessions: sessions,
            breaks: breaks,
            settings: settings,
            calendar: .current,
            holidayDates: holidayStore.dates
        )
    }

    private var scenarioUnitPay: Decimal? {
        guard let value = Decimal(string: scenarioGrossPerShift,
                                  locale: Locale(identifier: "en_US_POSIX")), value > 0 else {
            return nil
        }
        return value
    }

    private var scenarioProjectedGross: Decimal? {
        guard scenarioAdditionalShifts == 0 || scenarioUnitPay != nil else { return nil }
        return ManualPayScenario.projectedGross(
            recordedGross: summary.total + statusForecast.confirmedGross + statusForecast.appliedGross,
            shiftCount: scenarioAdditionalShifts,
            grossPerShift: scenarioUnitPay ?? 0
        )
    }

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
            pensionEnrollment: summary.completedDays >= 8 ? .enrolled : .notEnrolled,
            healthEnrollment: summary.completedDays >= 8 ? .enrolled : .notEnrolled,
            pensionBase: summary.total,
            healthBase: summary.total
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

    private func allowanceType(for name: String, period: IncentivePeriod, days: Int) -> String? {
        if period == .monthly && days == 15 { return "winner" }
        if period == .weekly && days == 5 { return "weekly" }
        if period == .weekly && days == 6 { return "special" }
        return nil
    }

    private func estimatedIncludedBonuses(for sessionID: UUID, types: Set<String>) -> Decimal {
        guard let session = sessions.first(where: { $0.id == sessionID }) else { return 0 }
        let day = Calendar.current.startOfDay(for: session.startAt)
        let relevant = earnedIncentives.filter { Calendar.current.isDate($0.day, inSameDayAs: day) }
        return relevant.reduce(Decimal.zero) { total, item in
            guard let workplace = workplaces.first(where: { $0.id == session.workplaceID }),
                  let rule = rules.first(where: {
                      $0.name == item.name && $0.workplaceID == workplace.id
                  }),
                  let type = allowanceType(for: rule.name, period: rule.period,
                                           days: rule.requiredAttendanceDays),
                  types.contains(type) else { return total }
            return total + item.amount
        }
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
        // Replace each recorded shift estimate. Explicitly included earned
        // incentives are removed once so they cannot be counted twice.
        let base = ActualPayReconciliation.total(
            estimatedMonthlyNet: estimatedTakeHome.net,
            shiftGross: audit.entries.map { (id: $0.id, gross: $0.grossTotal) },
            actualBySession: actualBySession,
            bonusNetBySession: weeklyBonusNetBySession,
            bonusInclusionBySession: bonusInclusionBySession
        )
        let typedBonusAdjustment = receivedPay.filter {
            $0.basis == .net && $0.sessionID != nil && !$0.includedBonusTypes.isEmpty
        }.reduce(Decimal.zero) { result, receipt in
            guard let id = receipt.sessionID else { return result }
            let gross = estimatedIncludedBonuses(for: id, types: receipt.includedBonusTypes)
            let estimated = EstimatedTakeHomeCalculator.calculate(gross: gross, shifts: []).net
            // Old single bonus picker is disabled for newly edited receipts.
            return result - estimated
        }
        return weeklyAllowanceTimeline.reduce(base + typedBonusAdjustment) { sum, item in
            guard let actual = item.separatelyReceivedNet,
                  item.inclusion != .included else { return sum }
            let estimated = EstimatedTakeHomeCalculator.calculate(gross: item.amount, shifts: []).net
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

    private func localizedBonusName(_ name: String) -> String {
        switch name {
        case "5-day weekly bonus": return appLocale.language.languageCode?.identifier == "ko" ? "주 5일 근무 주휴수당" : name
        case "6-day weekly bonus": return appLocale.language.languageCode?.identifier == "ko" ? "주 6일 근무 특근수당" : name
        case "15-day monthly bonus": return appLocale.language.languageCode?.identifier == "ko" ? "월 15일 위너프로모션" : name
        default: return name
        }
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
                            Text("월말 수입 시나리오")
                                .font(WakTypography.screenTitle)
                            Text("불규칙한 근무 일정은 자동 예측하지 않습니다. 아래 추가 근무 횟수와 1회 세전 급여를 직접 입력해 비교하세요.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)

                            row("현재 기록 기반 월 급여", money(summary.total))
                            row("확정 예정 근무", "\(statusForecast.confirmedCount)회 · \(money(statusForecast.confirmedGross))")
                            row("지원 중인 근무", "\(statusForecast.appliedCount)회 · \(money(statusForecast.appliedGross))")

                            Stepper(value: $scenarioAdditionalShifts, in: 0...31) {
                                Text("추가 근무 가정: \(scenarioAdditionalShifts)회")
                                    .font(.subheadline)
                            }
                            HStack {
                                Text("추가 1회 세전 급여")
                                    .font(.subheadline)
                                Spacer()
                                TextField("금액 입력", text: $scenarioGrossPerShift)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(maxWidth: 130)
                                    .accessibilityIdentifier("finance.scenario.grossPerShift")
                                Text("원")
                            }
                            if let scenarioProjectedGross {
                                Divider()
                                row("모든 예정 근무 포함 시 세전", money(scenarioProjectedGross))
                                row("추가 가정분", money(ManualPayScenario.additionalGross(
                                    shiftCount: scenarioAdditionalShifts,
                                    grossPerShift: scenarioUnitPay ?? 0
                                )))
                                row("예상 실수령액(단순 보험료 추정)",
                                    money(EstimatedTakeHomeCalculator.calculate(
                                        gross: scenarioProjectedGross, shifts: []
                                    ).net))
                            } else {
                                Text("추가 근무 1회 세전 급여를 입력하면 시나리오를 계산합니다.")
                                    .font(.caption).foregroundStyle(.orange)
                            }
                            if statusForecast.unpricedCount > 0 {
                                Text("금액을 계산할 수 없는 기존 근무 \(statusForecast.unpricedCount)건은 시나리오에서 제외했습니다.")
                                    .font(.caption).foregroundStyle(.orange)
                            }
                            Text("시나리오는 확정·지원 상태의 근무가 실제 완료된다고 가정한 참고값입니다. 추가 근무 횟수는 저장되지 않으며, 주휴·추가 인센티브 발생 및 세금은 새 가정에 대해 재계산하지 않습니다.")
                                .font(.caption).foregroundStyle(.secondary)
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
                                .foregroundStyle(CoufunchColor.primary)
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
                                Text("8일 이상 근무 기준 예상 보험료·추징액 (실제 가입·부과액과 다를 수 있음)")
                                    .font(.caption).foregroundStyle(.secondary)
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
                            Button {
                                showPayrollExportOptions = true
                            } label: {
                                Label("급여 내역 파일 공유", systemImage: "square.and.arrow.up")
                            }
                            .disabled(audit.entries.isEmpty && earnedIncentives.isEmpty)
                            if let payrollCSVError {
                                Text(payrollCSVError)
                                    .font(.caption).foregroundStyle(.red)
                            }
                            Text("공유 버튼을 누른 뒤 CSV 또는 TXT 파일 형식을 선택할 수 있습니다.")
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
                            if payrollDetailMode == .calendar && visibleAuditEntries.isEmpty {
                                ForEach(earnedIncentives.filter {
                                    Calendar.current.isDate($0.day, inSameDayAs: selectedPayrollDay)
                                }) { bonus in
                                    row(localizedBonusName(bonus.name), money(bonus.amount))
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
                                    let awards = assignedIncentives(for: item)
                                    let incentiveGross = awards.reduce(Decimal.zero) { $0 + $1.amount }
                                    ForEach(awards) { bonus in
                                        row(localizedBonusName(bonus.name), money(bonus.amount))
                                    }
                                    row("Shift gross (including earned incentives)", money(item.grossTotal + incentiveGross))
                                    row("Shift estimated net (including earned incentives)",
                                        money(EstimatedTakeHomeCalculator.calculate(
                                            gross: item.grossTotal + incentiveGross, shifts: []
                                        ).net))
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
                                        receiptGrossAmount = receivedPay.first(where: { $0.sessionID == item.id })?.grossAmount.map { NSDecimalNumber(decimal: $0).stringValue } ?? ""
                                        receiptError = nil
                                        bonusInclusion = .unknown
                                        receiptIncludedTypes = receivedPay.first(where: { $0.sessionID == item.id })?.includedBonusTypes ?? []
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
                    TextField("Actual net received (required, KRW)", text: $receiptAmount)
                        .keyboardType(.numberPad)
                    TextField("Actual gross before deductions (optional, KRW)", text: $receiptGrossAmount)
                        .keyboardType(.numberPad)
                    DatePicker("Bank deposit date", selection: $depositDate, displayedComponents: .date)
                    Text("The deposit date is recorded separately from the work date and does not change which month earned pay belongs to.")
                        .font(.caption).foregroundStyle(.secondary)
                    Section("Included in actual deposit") {
                        Toggle("Includes weekly allowance (5 days)", isOn: Binding(
                            get: { receiptIncludedTypes.contains("weekly") },
                            set: { if $0 { receiptIncludedTypes.insert("weekly") } else { receiptIncludedTypes.remove("weekly") } }
                        ))
                        Toggle("Includes special allowance (6 days)", isOn: Binding(
                            get: { receiptIncludedTypes.contains("special") },
                            set: { if $0 { receiptIncludedTypes.insert("special") } else { receiptIncludedTypes.remove("special") } }
                        ))
                        Toggle("Includes Winner Promotion (15 days)", isOn: Binding(
                            get: { receiptIncludedTypes.contains("winner") },
                            set: { if $0 { receiptIncludedTypes.insert("winner") } else { receiptIncludedTypes.remove("winner") } }
                        ))
                        Text("Choose only allowances included in this bank deposit. Unchecked allowances stay in the estimate.")
                            .font(.caption).foregroundStyle(.secondary)
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
        .confirmationDialog("공유 파일 형식 선택", isPresented: $showPayrollExportOptions, titleVisibility: .visible) {
            Button("CSV 파일") { exportPayrollCSV() }
            Button("TXT 파일") { exportPayrollText() }
            Button("취소", role: .cancel) { }
        }
        .sheet(item: $payrollCSVAttachment) { file in
            PayrollCSVShareSheet(items: [file.url])
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

    private func exportPayrollCSV() {
        let calendar = Calendar.current
        let bonusRows = earnedIncentives.map {
            (date: $0.day, name: localizedBonusName($0.name), amount: $0.amount)
        }
        let content = PayrollAuditCSV.readable(report: audit, calendar: calendar,
                                               incentives: bonusRows,
                                               actualNetBySession: actualBySession,
                                               totalNet: reconciledNet,
                                               locale: appLocale)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        formatter.calendar = calendar
        let filename = "Coufunch_\(appLocale.language.languageCode?.identifier == "ko" ? "급여내역" : "Payroll")_\(formatter.string(from: selectedMonth)).csv"
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CoufunchPayrollExports", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true
            )
            let url = directory.appendingPathComponent(filename)
            // UTF-8 BOM makes Korean headers reliably readable in Excel.
            try (Data([0xEF, 0xBB, 0xBF]) + Data(content.utf8)).write(
                to: url, options: .atomic
            )
            payrollCSVError = nil
            payrollCSVAttachment = PayrollCSVAttachment(url: url)
        } catch {
            payrollCSVError = "급여 CSV 파일을 생성하지 못했습니다."
        }
    }

    private func exportPayrollText() {
        let calendar = Calendar.current
        let korean = appLocale.language.languageCode?.identifier == "ko"
        func l(_ ko: String, _ en: String) -> String { korean ? ko : en }
        let date = DateFormatter()
        date.locale = appLocale
        date.dateFormat = "yyyy-MM-dd"
        date.timeZone = calendar.timeZone
        let month = DateFormatter()
        month.dateFormat = "yyyy-MM"
        let lines = audit.entries.sorted(by: { $0.start < $1.start }).map { entry in
            let actual = actualBySession[entry.id]
            let net = actual ?? EstimatedTakeHomeCalculator.calculate(gross: entry.grossTotal, shifts: []).net
            return "\(date.string(from: entry.start)) | \(entry.workplaceName) | \(l("세전", "Gross")) \(money(entry.grossTotal)) | \(l("세후", "Net")) \(money(net)) (\(actual == nil ? l("예상", "Estimated") : l("실제", "Actual")))"
        }
        let awards = earnedIncentives.sorted(by: { $0.day < $1.day }).map { bonus in
            let net = EstimatedTakeHomeCalculator.calculate(gross: bonus.amount, shifts: []).net
            return "\(date.string(from: bonus.day)) | \(localizedBonusName(bonus.name)) | \(l("세전", "Gross")) +\(money(bonus.amount)) | \(l("세후 예상", "Estimated net")) +\(money(net))"
        }
        let content = ([
            "\(l("쿠펀치 급여 내역", "Coufunch Payroll Report")) (\(month.string(from: selectedMonth)))",
            "--------------------------------",
            "\(l("완료 근무", "Completed days")): \(summary.completedDays)\(korean ? "일" : "")",
            "\(l("기본급", "Base pay")): \(money(summary.basePay))",
            "\(l("야간수당", "Night premium")): \(money(summary.nightPremium))",
            "\(l("연장수당", "Overtime premium")): \(money(summary.overtimePremium))",
            "\(l("휴일수당", "Holiday premium")): \(money(summary.holidayPremium))",
            "\(l("자동 인센티브", "Automatic incentives")): \(money(summary.automaticIncentives))",
            "\(l("수동 인센티브", "Manual incentives")): \(money(summary.manualIncentives))",
            "\(l("세전 총액", "Gross total")): \(money(summary.total))",
            "\(l("세후 합계 (실제 입력 우선, 나머지 예상)", "Net total (actual first, estimated otherwise)")): \(money(reconciledNet))",
            "\(l("일평균 세전", "Average daily gross")): \(money(summary.dailyAverage))",
            "--------------------------------",
            l("근무별 내역 (세전 / 세후)", "Shift details (gross / net)"),
        ] + lines + ["", l("인센티브", "Incentives")] + awards + [
            "", l("※ 실제 입력된 금액은 실제로, 미입력 금액은 예상으로 표기합니다.", "Actual amounts are labeled Actual; missing amounts are labeled Estimated."),
            l("※ 수당 세후 예상은 참고용이며, 세후 합계에 중복 합산하지 않습니다.", "Estimated net bonuses are informational and are not added again to the net total.")
        ]).joined(separator: "\n") + "\n"
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CoufunchPayrollExports", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(
                "Coufunch_\(l("급여내역", "Payroll"))_\(month.string(from: selectedMonth)).txt"
            )
            try Data(content.utf8).write(to: url, options: .atomic)
            payrollCSVError = nil
            payrollCSVAttachment = PayrollCSVAttachment(url: url)
        } catch {
            payrollCSVError = "급여 TXT 파일을 생성하지 못했습니다."
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
              (receiptGrossAmount.isEmpty || (
                  Decimal(string: receiptGrossAmount, locale: Locale(identifier: "en_US_POSIX")) ?? -1
              ) >= 0),
              let entry = audit.entries.first(where: { $0.id == id }),
              let month = Calendar.current.dateInterval(of: .month, for: entry.start)?.start else {
            receiptError = "Enter a valid non-negative payment amount."
            return
        }
        let grossAmount = receiptGrossAmount.isEmpty ? nil : Decimal(string: receiptGrossAmount, locale: Locale(identifier: "en_US_POSIX"))
        let existing = receivedPay.filter { $0.sessionID == id }
        if let first = existing.first {
            first.amount = amount
            first.grossAmount = grossAmount
            first.basis = .net
            first.bonusInclusion = .unknown
            first.includedBonusTypes = receiptIncludedTypes
            first.depositedAt = depositDate
            for duplicate in existing.dropFirst() { modelContext.delete(duplicate) }
        } else {
            modelContext.insert(ReceivedPayRecord(monthStart: month, amount: amount,
                                                   basis: .net, sessionID: id,
                                                   bonusInclusion: .unknown,
                                                   depositedAt: depositDate,
                                                   includedBonusTypes: receiptIncludedTypes,
                                                   grossAmount: grossAmount))
        }
        do {
            try modelContext.save()
            editingSessionID = nil
            receiptError = nil
            Task { await refreshPaydayRemindersAfterReceiptChange() }
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
            Task { await refreshPaydayRemindersAfterReceiptChange() }
        } catch {
            modelContext.rollback()
            receiptError = "Unable to delete the payment record."
        }
    }

    /// Use a fresh SwiftData snapshot after the successful save. @Query changes
    /// may not have published yet when the notification refresh starts.
    @MainActor
    private func refreshPaydayRemindersAfterReceiptChange() async {
        guard UserDefaults.standard.bool(forKey: "paydayRemindersEnabled") else { return }
        do {
            let currentSessions = try modelContext.fetch(FetchDescriptor<WorkSession>())
            let currentBreaks = try modelContext.fetch(FetchDescriptor<WorkBreak>())
            let currentWorkplaces = try modelContext.fetch(FetchDescriptor<Workplace>())
            let currentSettings = try modelContext.fetch(FetchDescriptor<WorkplacePaySettings>())
            let currentRules = try modelContext.fetch(FetchDescriptor<IncentiveRule>())
            let currentReceipts = try modelContext.fetch(FetchDescriptor<ReceivedPayRecord>())

            // Load holidays for the current year and next year because reminders
            // can cross the year boundary. Failure leaves dates unavailable rather
            // than incorrectly assuming a weekday is not a public holiday.
            let year = Calendar.current.component(.year, from: Date())
            await holidayStore.load(year: year)
            await holidayStore.load(year: year + 1)

            await PaydayReminderScheduler.synchronize(
                sessions: currentSessions,
                holidays: holidayStore.dates,
                workplaces: currentWorkplaces,
                rules: currentRules,
                loadedYears: holidayStore.loadedYears,
                breaks: currentBreaks,
                paySettings: currentSettings,
                receivedPay: currentReceipts
            )
        } catch {
            NSLog("Coufunch payday refresh after receipt change failed: %@", String(describing: error))
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

private struct PayrollCSVAttachment: Identifiable {
    let id = UUID()
    let url: URL
}

private struct PayrollCSVShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

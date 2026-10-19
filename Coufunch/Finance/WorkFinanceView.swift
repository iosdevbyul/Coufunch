import SwiftUI
import SwiftData
import WakTrainerDesignSystem

struct WorkFinanceView: View {
    enum Screen { case pay, strategy }
    let screen: Screen

    @Query private var sessions: [WorkSession]
    @Query private var breaks: [WorkBreak]
    @Query private var workplaces: [Workplace]
    @Query private var settings: [WorkplacePaySettings]
    @Query private var rules: [IncentiveRule]
    @Query private var manual: [ManualIncentive]
    @State private var selectedMonth = Date()

    private var summary: MonthlyPaySummary {
        WorkFinanceSummary.summarize(month: selectedMonth, sessions: sessions,
            breaks: breaks, workplaces: workplaces, settings: settings,
            rules: rules, manual: manual, calendar: .current)
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
                    WakCard {
                        VStack(alignment: .leading, spacing: WakSpacing.medium) {
                            Text("Estimated Gross Pay").font(WakTypography.screenTitle)
                            Text(money(summary.total)).font(.title.bold()).foregroundStyle(WakColor.primary)
                            row("Completed days", "\(summary.completedDays)")
                            row("Base pay", money(summary.basePay))
                            row("Night premium", money(summary.nightPremium))
                            row("Overtime premium", money(summary.overtimePremium))
                            row("Automatic incentives", money(summary.automaticIncentives))
                            row("Manual incentives", money(summary.manualIncentives))
                            row("Average per completed day", money(summary.dailyAverage))
                            if summary.skippedSessions > 0 {
                                Text("\(summary.skippedSessions) incomplete pay record(s) excluded.")
                                    .font(.footnote).foregroundStyle(.orange)
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
                        WakCard {
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
                    Text("These opportunities depend on approval and qualifying completed workdays. Daily wages are not included in the potential bonus.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(WakSpacing.large)
        }
        .background(WakColor.background)
        .navigationTitle(screen == .pay ? "Pay & Allowances" : "Work Strategy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.semibold)
        }
        .font(.subheadline)
    }
}

import SwiftUI
import SwiftData
import WakTrainerDesignSystem

struct WorkFinanceView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var receivedPay: [ReceivedPayRecord]
    @State private var receiptAmount = ""
    @State private var receiptBasis: ReceivedPayBasis = .net
    @State private var receiptNote = ""
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

    private var summary: MonthlyPaySummary {
        WorkFinanceSummary.summarize(month: selectedMonth, sessions: sessions,
            breaks: breaks, workplaces: workplaces, settings: settings,
            rules: rules, manual: manual, calendar: .current)
    }

    private var forecast: PayForecast {
        PayForecastCalculator.calculate(month: selectedMonth, sessions: sessions,
            breaks: breaks, settings: settings, calendar: .current)
    }

    private var selectedReceipts: [ReceivedPayRecord] {
        guard let interval = Calendar.current.dateInterval(of: .month, for: selectedMonth) else { return [] }
        return receivedPay.filter { interval.contains($0.monthStart) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private var receivedGross: Decimal {
        selectedReceipts.filter { $0.basis == .gross }.reduce(Decimal.zero) { $0 + $1.amount }
    }

    private var receivedNet: Decimal {
        selectedReceipts.filter { $0.basis == .net }.reduce(Decimal.zero) { $0 + $1.amount }
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
                    WakCard {
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
                                Text("\(forecast.unpricedCount) shift(s) without sufficient pay data.")
                                    .font(.caption).foregroundStyle(.orange)
                            }
                        }
                    }

                    WakCard {
                        VStack(alignment: .leading, spacing: WakSpacing.medium) {
                            Text("Actual Payments").font(WakTypography.screenTitle)
                            Text("Record gross or take-home deposits separately. Only gross receipts can be compared to the estimated gross amount.")
                                .font(.footnote).foregroundStyle(.secondary)
                            ForEach(selectedReceipts) { receipt in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(money(receipt.amount))
                                        Text(receipt.basis == .gross ? "Gross received" : "Net received")
                                            .font(.caption).foregroundStyle(.secondary)
                                        if !receipt.note.isEmpty {
                                            Text(receipt.note).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Button(role: .destructive) { remove(receipt) } label: {
                                        Image(systemName: "trash")
                                    }
                                    .accessibilityLabel("Delete payment record")
                                }
                            }
                            row("Gross receipts", money(receivedGross))
                            row("Net receipts", money(receivedNet))
                            if selectedReceipts.contains(where: { $0.basis == .gross }) {
                                row("Gross difference (received − estimated)",
                                    money(receivedGross - summary.total))
                            } else {
                                Text("No gross payment recorded; gross difference is unavailable.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }

                            Picker("Received as", selection: $receiptBasis) {
                                Text("Take-home / net").tag(ReceivedPayBasis.net)
                                Text("Before deductions / gross").tag(ReceivedPayBasis.gross)
                            }
                            .pickerStyle(.segmented)
                            TextField("Amount received (KRW)", text: $receiptAmount)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.roundedBorder)
                            TextField("Payment note (optional)", text: $receiptNote)
                                .textFieldStyle(.roundedBorder)
                            if let receiptError {
                                Text(receiptError).font(.footnote).foregroundStyle(.red)
                            }
                            Button("Add Payment") { addReceipt() }
                                .buttonStyle(.borderedProminent)
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

    private func addReceipt() {
        guard let amount = Decimal(string: receiptAmount, locale: Locale(identifier: "en_US_POSIX")),
              amount >= 0,
              let month = Calendar.current.dateInterval(of: .month, for: selectedMonth)?.start else {
            receiptError = "Enter a valid non-negative payment amount."
            return
        }
        modelContext.insert(ReceivedPayRecord(monthStart: month, amount: amount,
                                               basis: receiptBasis, note: receiptNote))
        do {
            try modelContext.save()
            receiptAmount = ""
            receiptNote = ""
            receiptError = nil
        } catch {
            modelContext.rollback()
            receiptError = "Unable to save the payment record."
        }
    }

    private func remove(_ receipt: ReceivedPayRecord) {
        modelContext.delete(receipt)
        do {
            try modelContext.save()
            receiptError = nil
        } catch {
            modelContext.rollback()
            receiptError = "Unable to delete the payment record."
        }
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

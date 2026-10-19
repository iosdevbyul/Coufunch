import SwiftUI
import SwiftData
import WakTrainerDesignSystem

struct WorkplaceOnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var workplaceName = ""
    @State private var payMode: PayCalculationMode = .minimumHourly
    @State private var customRateText = ""
    @State private var fixedPayText = ""
    @State private var nightPremiumEnabled = true
    @State private var incentiveChoice: IncentiveChoice = .preset
    @State private var customRuleName = ""
    @State private var customPeriod: IncentivePeriod = .weekly
    @State private var customRequiredDays = 5
    @State private var customAmountText = ""
    @State private var customStacking = true
    @State private var step = 0
    @State private var errorMessage: String?

    let onComplete: () -> Void

    private enum IncentiveChoice: String, CaseIterable {
        case preset, custom, none
    }

    private var trimmedName: String {
        workplaceName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func decimal(_ raw: String) -> Decimal? {
        Decimal(string: raw.trimmingCharacters(in: .whitespacesAndNewlines),
                locale: Locale(identifier: "en_US_POSIX"))
    }

    private var payIsValid: Bool {
        switch payMode {
        case .minimumHourly: true
        case .customHourly: customRateText.isEmpty == false && (decimal(customRateText) ?? -1) > 0
        case .fixedDaily: fixedPayText.isEmpty == false && (decimal(fixedPayText) ?? -1) >= 0
        }
    }

    private var ruleIsValid: Bool {
        incentiveChoice != .custom ||
        (!customRuleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
         && (decimal(customAmountText) ?? -1) >= 0)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WakSpacing.large) {
                    Text("Step \(step + 1) of 3")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WakColor.primary)

                    switch step {
                    case 0: workplaceStep
                    case 1: payStep
                    default: incentiveStep
                    }

                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red).font(.footnote)
                    }

                    HStack {
                        if step > 0 {
                            Button("Back") { step -= 1; errorMessage = nil }
                                .buttonStyle(.bordered)
                        }
                        Spacer()
                        Button(step == 2 ? "Finish Setup" : "Continue") {
                            if step < 2 {
                                step += 1
                            } else {
                                save()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(step == 0 ? trimmedName.isEmpty :
                                  step == 1 ? !payIsValid : !ruleIsValid)
                    }
                }
                .padding(WakSpacing.large)
            }
            .background(WakColor.background)
            .navigationTitle("Set Up Coufunch")
            .navigationBarTitleDisplayMode(.inline)
        }
        .tint(WakColor.primary)
        .preferredColorScheme(.dark)
    }

    private var workplaceStep: some View {
        VStack(alignment: .leading, spacing: WakSpacing.medium) {
            Text("Your Workplace")
                .font(WakTypography.screenTitle)
                .foregroundStyle(WakColor.textPrimary)
            Text("Enter any name you like. Coufunch does not download employer or work center names.")
                .foregroundStyle(.secondary)
            TextField("Workplace name", text: $workplaceName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .padding()
                .background(WakColor.textPrimary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var payStep: some View {
        VStack(alignment: .leading, spacing: WakSpacing.medium) {
            Text("Pay Method")
                .font(WakTypography.screenTitle)
            Picker("Calculation", selection: $payMode) {
                Text("Minimum hourly wage").tag(PayCalculationMode.minimumHourly)
                Text("Custom hourly wage").tag(PayCalculationMode.customHourly)
                Text("Fixed daily pay").tag(PayCalculationMode.fixedDaily)
            }
            .pickerStyle(.inline)
            if payMode == .customHourly {
                TextField("Hourly wage (KRW)", text: $customRateText)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
            } else if payMode == .fixedDaily {
                TextField("Daily pay (KRW)", text: $fixedPayText)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
            } else {
                Text("The statutory minimum wage will be selected for the work date when the session is recorded.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Toggle("Include night work premium (22:00–06:00)", isOn: $nightPremiumEnabled)
                .disabled(payMode == .fixedDaily)
            Text("Pay estimates exclude taxes, insurance and other deductions. Fixed daily pay will not receive an extra automatic night premium.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var incentiveStep: some View {
        VStack(alignment: .leading, spacing: WakSpacing.medium) {
            Text("Incentive Setup")
                .font(WakTypography.screenTitle)
            Text("These optional example rules may not match your workplace. You can edit them later.")
                .foregroundStyle(.secondary)
            Picker("Incentives", selection: $incentiveChoice) {
                Text("Use example rules").tag(IncentiveChoice.preset)
                Text("Enter my own rule").tag(IncentiveChoice.custom)
                Text("No incentives").tag(IncentiveChoice.none)
            }
            .pickerStyle(.inline)
            switch incentiveChoice {
            case .preset:
                VStack(alignment: .leading, spacing: 8) {
                    Text("5 days per week: +80,000 KRW")
                    Text("6 days per week: +40,000 KRW (stackable)")
                    Text("15 days per month: +70,000 KRW")
                    Text("Week: Sunday–Saturday")
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
            case .custom:
                TextField("Rule name", text: $customRuleName)
                    .textFieldStyle(.roundedBorder)
                Picker("Period", selection: $customPeriod) {
                    Text("Day").tag(IncentivePeriod.daily)
                    Text("Week").tag(IncentivePeriod.weekly)
                    Text("Month").tag(IncentivePeriod.monthly)
                }
                Stepper("Required attendance days: \(customRequiredDays)",
                        value: $customRequiredDays,
                        in: 1...(customPeriod == .daily ? 1 : customPeriod == .weekly ? 7 : 31))
                TextField("Bonus amount (KRW)", text: $customAmountText)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                Toggle("Allow stacking with other bonuses", isOn: $customStacking)
            case .none:
                Text("You can add incentive rules later.")
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: customPeriod) { _, newPeriod in
            customRequiredDays = min(customRequiredDays,
                                     newPeriod == .daily ? 1 : newPeriod == .weekly ? 7 : 31)
        }
    }

    private func save() {
        let workplace = Workplace(name: trimmedName, weekStartWeekday: 1)
        let settings = WorkplacePaySettings(
            workplaceID: workplace.id,
            payMode: payMode,
            customHourlyRate: payMode == .customHourly ? decimal(customRateText) : nil,
            fixedDailyPay: payMode == .fixedDaily ? decimal(fixedPayText) : nil,
            nightPremiumEnabled: payMode == .fixedDaily ? false : nightPremiumEnabled
        )
        modelContext.insert(workplace)
        modelContext.insert(settings)
        switch incentiveChoice {
        case .preset:
            IncentivePreset.exampleRules(workplaceID: workplace.id).forEach(modelContext.insert)
        case .custom:
            modelContext.insert(IncentiveRule(
                workplaceID: workplace.id,
                name: customRuleName.trimmingCharacters(in: .whitespacesAndNewlines),
                period: customPeriod,
                requiredAttendanceDays: customRequiredDays,
                amount: decimal(customAmountText) ?? 0,
                canStack: customStacking
            ))
        case .none:
            break
        }
        do {
            try modelContext.save()
            onComplete()
        } catch {
            modelContext.rollback()
            errorMessage = "Could not save the workplace. Please try again."
        }
    }
}

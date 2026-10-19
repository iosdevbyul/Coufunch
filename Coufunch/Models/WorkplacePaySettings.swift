import Foundation
import SwiftData

/// Workplace-level defaults. Session-specific pay snapshots remain authoritative.
@Model
final class WorkplacePaySettings {
    @Attribute(.unique) var id: UUID
    var workplaceID: UUID
    var payModeRaw: String
    var customHourlyRate: Decimal?
    var fixedDailyPay: Decimal?
    var nightPremiumEnabled: Bool
    var createdAt: Date

    var payMode: PayCalculationMode {
        get { PayCalculationMode(rawValue: payModeRaw) ?? .minimumHourly }
        set { payModeRaw = newValue.rawValue }
    }

    init(
        workplaceID: UUID,
        payMode: PayCalculationMode,
        customHourlyRate: Decimal? = nil,
        fixedDailyPay: Decimal? = nil,
        nightPremiumEnabled: Bool = true
    ) {
        self.id = UUID()
        self.workplaceID = workplaceID
        self.payModeRaw = payMode.rawValue
        self.customHourlyRate = customHourlyRate
        self.fixedDailyPay = fixedDailyPay
        self.nightPremiumEnabled = nightPremiumEnabled
        self.createdAt = .now
    }
}

/// These are opt-in examples, not claims of any employer's current policy.
enum IncentivePreset {
    static func exampleRules(workplaceID: UUID) -> [IncentiveRule] {
        [
            IncentiveRule(workplaceID: workplaceID, name: "5-day weekly bonus",
                          period: .weekly, requiredAttendanceDays: 5,
                          amount: 80_000, canStack: true),
            IncentiveRule(workplaceID: workplaceID, name: "6-day weekly bonus",
                          period: .weekly, requiredAttendanceDays: 6,
                          amount: 40_000, canStack: true),
            IncentiveRule(workplaceID: workplaceID, name: "15-day monthly bonus",
                          period: .monthly, requiredAttendanceDays: 15,
                          amount: 70_000, canStack: true)
        ]
    }
}

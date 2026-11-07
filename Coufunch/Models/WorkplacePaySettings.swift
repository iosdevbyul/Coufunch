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
    var overtimePremiumEnabled: Bool = true
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
        nightPremiumEnabled: Bool = true,
        overtimePremiumEnabled: Bool = true
    ) {
        self.id = UUID()
        self.workplaceID = workplaceID
        self.payModeRaw = payMode.rawValue
        self.customHourlyRate = customHourlyRate
        self.fixedDailyPay = fixedDailyPay
        self.nightPremiumEnabled = nightPremiumEnabled
        self.overtimePremiumEnabled = overtimePremiumEnabled
        self.createdAt = .now
    }
}

/// Opt-in 2026 examples using an eight-hour day at KRW 10,320/hour.
/// They are snapshots, not an automatic employer-policy update or a recurring wage formula.
enum IncentivePreset {
    static func exampleRules(workplaceID: UUID) -> [IncentiveRule] {
        [
            IncentiveRule(workplaceID: workplaceID, name: "5-day weekly bonus",
                          period: .weekly, requiredAttendanceDays: 5,
                          amount: 82_560, canStack: true),
            IncentiveRule(workplaceID: workplaceID, name: "6-day weekly bonus",
                          period: .weekly, requiredAttendanceDays: 6,
                          amount: 41_280, canStack: true),
            IncentiveRule(workplaceID: workplaceID, name: "15-day monthly bonus",
                          period: .monthly, requiredAttendanceDays: 15,
                          amount: 70_000, canStack: true)
        ]
    }
}

import Foundation
import SwiftData

/// Net or gross actually received. Users select the basis explicitly;
/// received net must not be silently compared with estimated gross.
enum ReceivedPayBasis: String, Codable, CaseIterable {
    case gross
    case net
}

enum BonusInclusion: String, Codable, CaseIterable {
    case unknown
    case included
    case excluded
}

@Model
final class ReceivedPayRecord {
    @Attribute(.unique) var id: UUID
    var monthStart: Date
    var workplaceID: UUID?
    var sessionID: UUID?
    var bonusInclusionRaw: String = "unknown"
    // Comma-separated allowance categories recorded with the actual deposit.
    var includedBonusTypesRaw: String = ""

    var bonusInclusion: BonusInclusion {
        get { BonusInclusion(rawValue: bonusInclusionRaw) ?? .unknown }
        set { bonusInclusionRaw = newValue.rawValue }
    }
    var includedBonusTypes: Set<String> {
        get { Set(includedBonusTypesRaw.split(separator: ",").map(String.init)) }
        set { includedBonusTypesRaw = newValue.sorted().joined(separator: ",") }
    }
    var amount: Decimal
    // Optional pre-deduction amount for a net actual receipt.
    var grossAmount: Decimal?
    var basisRaw: String
    var note: String
    var createdAt: Date
    // Nil for historical records where the actual bank deposit date was not recorded.
    var depositedAt: Date?
    // Stable award identity for a separately deposited weekly allowance.
    var allowanceAwardID: String?

    var basis: ReceivedPayBasis {
        get { ReceivedPayBasis(rawValue: basisRaw) ?? .net }
        set { basisRaw = newValue.rawValue }
    }

    init(id: UUID = UUID(), monthStart: Date, workplaceID: UUID? = nil,
         amount: Decimal, basis: ReceivedPayBasis, note: String = "", sessionID: UUID? = nil,
         bonusInclusion: BonusInclusion = .unknown, depositedAt: Date? = nil,
         allowanceAwardID: String? = nil, includedBonusTypes: Set<String> = [],
         grossAmount: Decimal? = nil) {
        self.id = id
        self.monthStart = monthStart
        self.workplaceID = workplaceID
        self.sessionID = sessionID
        self.bonusInclusionRaw = bonusInclusion.rawValue
        self.includedBonusTypesRaw = includedBonusTypes.sorted().joined(separator: ",")
        self.amount = amount
        self.grossAmount = grossAmount
        self.basisRaw = basis.rawValue
        self.note = note
        self.createdAt = .now
        self.depositedAt = depositedAt
        self.allowanceAwardID = allowanceAwardID
    }
}

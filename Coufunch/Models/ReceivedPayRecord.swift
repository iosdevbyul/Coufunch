import Foundation
import SwiftData

/// Net or gross actually received. Users select the basis explicitly;
/// received net must not be silently compared with estimated gross.
enum ReceivedPayBasis: String, Codable, CaseIterable {
    case gross
    case net
}

@Model
final class ReceivedPayRecord {
    @Attribute(.unique) var id: UUID
    var monthStart: Date
    var workplaceID: UUID?
    var sessionID: UUID?
    var amount: Decimal
    var basisRaw: String
    var note: String
    var createdAt: Date

    var basis: ReceivedPayBasis {
        get { ReceivedPayBasis(rawValue: basisRaw) ?? .net }
        set { basisRaw = newValue.rawValue }
    }

    init(id: UUID = UUID(), monthStart: Date, workplaceID: UUID? = nil,
         amount: Decimal, basis: ReceivedPayBasis, note: String = "", sessionID: UUID? = nil) {
        self.id = id
        self.monthStart = monthStart
        self.workplaceID = workplaceID
        self.sessionID = sessionID
        self.amount = amount
        self.basisRaw = basis.rawValue
        self.note = note
        self.createdAt = .now
    }
}

import Foundation
import SwiftData

enum PayCalculationMode: String, Codable, CaseIterable {
    case minimumHourly
    case customHourly
    case fixedDaily
}

enum WorkSessionStatus: String, Codable, CaseIterable {
    case applied
    case confirmed
    case completed
}

enum IncentivePeriod: String, Codable, CaseIterable {
    case daily
    case weekly
    case monthly
}

@Model
final class Workplace {
    @Attribute(.unique) var id: UUID
    var name: String
    var weekStartWeekday: Int
    var createdAt: Date

    init(id: UUID = UUID(), name: String, weekStartWeekday: Int = 1, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.weekStartWeekday = weekStartWeekday
        self.createdAt = createdAt
    }
}

@Model
final class WorkSession {
    @Attribute(.unique) var id: UUID
    var workplaceID: UUID
    var startAt: Date
    var endAt: Date?
    var statusRaw: String
    var payModeRaw: String
    var hourlyRateSnapshot: Decimal?
    var fixedDailyPaySnapshot: Decimal?
    var recordedAt: Date

    var status: WorkSessionStatus {
        get { WorkSessionStatus(rawValue: statusRaw) ?? .applied }
        set { statusRaw = newValue.rawValue }
    }

    var payMode: PayCalculationMode {
        get { PayCalculationMode(rawValue: payModeRaw) ?? .minimumHourly }
        set { payModeRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        workplaceID: UUID,
        startAt: Date,
        endAt: Date? = nil,
        status: WorkSessionStatus = .applied,
        payMode: PayCalculationMode = .minimumHourly,
        hourlyRateSnapshot: Decimal? = nil,
        fixedDailyPaySnapshot: Decimal? = nil,
        recordedAt: Date = .now
    ) {
        self.id = id
        self.workplaceID = workplaceID
        self.startAt = startAt
        self.endAt = endAt
        self.statusRaw = status.rawValue
        self.payModeRaw = payMode.rawValue
        self.hourlyRateSnapshot = hourlyRateSnapshot
        self.fixedDailyPaySnapshot = fixedDailyPaySnapshot
        self.recordedAt = recordedAt
    }
}

@Model
final class WorkBreak {
    @Attribute(.unique) var id: UUID
    var sessionID: UUID
    var startAt: Date
    var endAt: Date

    init(id: UUID = UUID(), sessionID: UUID, startAt: Date, endAt: Date) {
        self.id = id
        self.sessionID = sessionID
        self.startAt = startAt
        self.endAt = endAt
    }
}

@Model
final class IncentiveRule {
    @Attribute(.unique) var id: UUID
    var workplaceID: UUID
    var name: String
    var periodRaw: String
    var requiredAttendanceDays: Int
    var amount: Decimal
    var canStack: Bool
    var isEnabled: Bool

    var period: IncentivePeriod {
        get { IncentivePeriod(rawValue: periodRaw) ?? .weekly }
        set { periodRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        workplaceID: UUID,
        name: String,
        period: IncentivePeriod,
        requiredAttendanceDays: Int,
        amount: Decimal,
        canStack: Bool = true,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.workplaceID = workplaceID
        self.name = name
        self.periodRaw = period.rawValue
        self.requiredAttendanceDays = requiredAttendanceDays
        self.amount = amount
        self.canStack = canStack
        self.isEnabled = isEnabled
    }
}

@Model
final class ManualIncentive {
    @Attribute(.unique) var id: UUID
    var workplaceID: UUID
    var sessionID: UUID?
    var earnedOn: Date
    var name: String
    var amount: Decimal

    init(
        id: UUID = UUID(),
        workplaceID: UUID,
        sessionID: UUID? = nil,
        earnedOn: Date,
        name: String,
        amount: Decimal
    ) {
        self.id = id
        self.workplaceID = workplaceID
        self.sessionID = sessionID
        self.earnedOn = earnedOn
        self.name = name
        self.amount = amount
    }
}

/// Sessions are attributed to the calendar date on which they begin.
/// Two sessions on the same date count as one attendance day per workplace.
enum WorkAttendance {
    static func uniqueDays(
        of sessions: [WorkSession],
        workplaceID: UUID,
        calendar: Calendar
    ) -> Set<Date> {
        Set(sessions.filter {
            $0.workplaceID == workplaceID && $0.status == .completed
        }.map { calendar.startOfDay(for: $0.startAt) })
    }
}

enum WorkSessionValidation {
    static func hasValidTimeRange(start: Date, end: Date) -> Bool {
        end > start
    }

    static func isValidBreak(
        start: Date,
        end: Date,
        workStart: Date,
        workEnd: Date
    ) -> Bool {
        start < end && start >= workStart && end <= workEnd
    }
}

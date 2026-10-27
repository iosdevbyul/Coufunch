import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Versioned, portable JSON backup for the seven SwiftData record types.
/// It intentionally does not claim to include UserDefaults-based preferences.
struct CoufunchBackupArchive: Codable {
    let version: Int
    let createdAt: Date
    let workplaces: [[String: String]]
    let paySettings: [[String: String]]
    let sessions: [[String: String]]
    let breaks: [[String: String]]
    let rules: [[String: String]]
    let incentives: [[String: String]]
    let receipts: [[String: String]]

    var recordCount: Int {
        workplaces.count + paySettings.count + sessions.count +
        breaks.count + rules.count + incentives.count + receipts.count
    }
}

struct CoufunchBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    static var writableContentTypes: [UTType] { [.json] }
    var archive: CoufunchBackupArchive

    init(archive: CoufunchBackupArchive) { self.archive = archive }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CoufunchBackupError.invalidFile
        }
        archive = try CoufunchBackupStore.decode(data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try CoufunchBackupStore.encode(archive))
    }
}

enum CoufunchBackupError: LocalizedError {
    case invalidFile
    case unsupportedVersion
    case invalidRecord(String)

    var errorDescription: String? {
        switch self {
        case .invalidFile: "백업 파일을 읽을 수 없습니다."
        case .unsupportedVersion: "지원하지 않는 백업 파일 버전입니다."
        case .invalidRecord(let reason): "백업 기록이 올바르지 않습니다: \(reason)"
        }
    }
}

enum CoufunchBackupStore {
    private static func string(_ value: Decimal?) -> String {
        value.map { NSDecimalNumber(decimal: $0).stringValue } ?? ""
    }
    private static func stamp(_ value: Date?) -> String {
        value.map { String($0.timeIntervalSince1970) } ?? ""
    }
    private static func flag(_ value: Bool?) -> String {
        value.map { $0 ? "true" : "false" } ?? ""
    }
    private static func uuid(_ value: UUID?) -> String { value?.uuidString ?? "" }

    static func create(from context: ModelContext) throws -> CoufunchBackupArchive {
        let workplaces = try context.fetch(FetchDescriptor<Workplace>())
        let settings = try context.fetch(FetchDescriptor<WorkplacePaySettings>())
        let sessions = try context.fetch(FetchDescriptor<WorkSession>())
        let breaks = try context.fetch(FetchDescriptor<WorkBreak>())
        let rules = try context.fetch(FetchDescriptor<IncentiveRule>())
        let incentives = try context.fetch(FetchDescriptor<ManualIncentive>())
        let receipts = try context.fetch(FetchDescriptor<ReceivedPayRecord>())

        return CoufunchBackupArchive(
            version: 1, createdAt: .now,
            workplaces: workplaces.map { [
                "id": uuid($0.id), "name": $0.name,
                "weekStartWeekday": String($0.weekStartWeekday),
                "createdAt": stamp($0.createdAt)
            ] },
            paySettings: settings.map { [
                "id": uuid($0.id), "workplaceID": uuid($0.workplaceID),
                "payMode": $0.payModeRaw,
                "customHourlyRate": string($0.customHourlyRate),
                "fixedDailyPay": string($0.fixedDailyPay),
                "nightPremiumEnabled": flag($0.nightPremiumEnabled),
                "overtimePremiumEnabled": flag($0.overtimePremiumEnabled),
                "createdAt": stamp($0.createdAt)
            ] },
            sessions: sessions.map { [
                "id": uuid($0.id), "workplaceID": uuid($0.workplaceID),
                "startAt": stamp($0.startAt), "endAt": stamp($0.endAt),
                "status": $0.statusRaw, "payMode": $0.payModeRaw,
                "hourlyRateSnapshot": string($0.hourlyRateSnapshot),
                "fixedDailyPaySnapshot": string($0.fixedDailyPaySnapshot),
                "recordedAt": stamp($0.recordedAt),
                "scheduledEndAt": stamp($0.scheduledEndAt),
                "nightPremiumSnapshot": flag($0.nightPremiumSnapshot),
                "overtimePremiumSnapshot": flag($0.overtimePremiumSnapshot)
            ] },
            breaks: breaks.map { [
                "id": uuid($0.id), "sessionID": uuid($0.sessionID),
                "startAt": stamp($0.startAt), "endAt": stamp($0.endAt)
            ] },
            rules: rules.map { [
                "id": uuid($0.id), "workplaceID": uuid($0.workplaceID),
                "name": $0.name, "period": $0.periodRaw,
                "requiredAttendanceDays": String($0.requiredAttendanceDays),
                "amount": string($0.amount), "canStack": flag($0.canStack),
                "isEnabled": flag($0.isEnabled)
            ] },
            incentives: incentives.map { [
                "id": uuid($0.id), "workplaceID": uuid($0.workplaceID),
                "sessionID": uuid($0.sessionID), "earnedOn": stamp($0.earnedOn),
                "name": $0.name, "amount": string($0.amount)
            ] },
            receipts: receipts.map { [
                "id": uuid($0.id), "monthStart": stamp($0.monthStart),
                "workplaceID": uuid($0.workplaceID), "sessionID": uuid($0.sessionID),
                "bonusInclusion": $0.bonusInclusionRaw,
                "includedBonusTypes": $0.includedBonusTypesRaw,
                "amount": string($0.amount), "grossAmount": string($0.grossAmount),
                "basis": $0.basisRaw, "note": $0.note,
                "createdAt": stamp($0.createdAt), "depositedAt": stamp($0.depositedAt),
                "allowanceAwardID": $0.allowanceAwardID ?? ""
            ] }
        )
    }

    static func encode(_ archive: CoufunchBackupArchive) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(archive)
    }

    static func decode(_ data: Data) throws -> CoufunchBackupArchive {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(CoufunchBackupArchive.self, from: data)
        guard archive.version == 1 else { throw CoufunchBackupError.unsupportedVersion }
        try validate(archive)
        return archive
    }

    private static func required(_ row: [String: String], _ key: String) throws -> String {
        guard let value = row[key], !value.isEmpty else {
            throw CoufunchBackupError.invalidRecord("missing \(key)")
        }
        return value
    }
    private static func identifier(_ row: [String: String], _ key: String = "id") throws -> UUID {
        guard let result = UUID(uuidString: try required(row, key)) else {
            throw CoufunchBackupError.invalidRecord("invalid \(key)")
        }
        return result
    }
    private static func optionalIdentifier(_ row: [String: String], _ key: String) throws -> UUID? {
        guard let raw = row[key], !raw.isEmpty else { return nil }
        guard let result = UUID(uuidString: raw) else {
            throw CoufunchBackupError.invalidRecord("invalid \(key)")
        }
        return result
    }
    private static func date(_ row: [String: String], _ key: String) throws -> Date {
        guard let timestamp = Double(try required(row, key)), timestamp.isFinite else {
            throw CoufunchBackupError.invalidRecord("invalid \(key)")
        }
        return Date(timeIntervalSince1970: timestamp)
    }
    private static func optionalDate(_ row: [String: String], _ key: String) throws -> Date? {
        guard let raw = row[key], !raw.isEmpty else { return nil }
        guard let timestamp = Double(raw), timestamp.isFinite else {
            throw CoufunchBackupError.invalidRecord("invalid \(key)")
        }
        return Date(timeIntervalSince1970: timestamp)
    }
    private static func number(_ row: [String: String], _ key: String) throws -> Int {
        guard let value = Int(try required(row, key)) else {
            throw CoufunchBackupError.invalidRecord("invalid \(key)")
        }
        return value
    }
    private static func decimal(_ row: [String: String], _ key: String) throws -> Decimal {
        guard let value = Decimal(string: try required(row, key), locale: Locale(identifier: "en_US_POSIX")) else {
            throw CoufunchBackupError.invalidRecord("invalid \(key)")
        }
        return value
    }
    private static func optionalDecimal(_ row: [String: String], _ key: String) throws -> Decimal? {
        guard let raw = row[key], !raw.isEmpty else { return nil }
        guard let value = Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX")) else {
            throw CoufunchBackupError.invalidRecord("invalid \(key)")
        }
        return value
    }
    private static func boolean(_ row: [String: String], _ key: String) throws -> Bool {
        switch try required(row, key) {
        case "true": return true
        case "false": return false
        default: throw CoufunchBackupError.invalidRecord("invalid \(key)")
        }
    }
    private static func optionalBoolean(_ row: [String: String], _ key: String) throws -> Bool? {
        guard let raw = row[key], !raw.isEmpty else { return nil }
        return try boolean(row, key)
    }

    private static func validate(_ archive: CoufunchBackupArchive) throws {
        var ids = Set<UUID>()
        for group in [archive.workplaces, archive.paySettings, archive.sessions,
                      archive.breaks, archive.rules, archive.incentives, archive.receipts] {
            for row in group {
                let id = try identifier(row)
                guard ids.insert(id).inserted else {
                    throw CoufunchBackupError.invalidRecord("duplicate ID \(id)")
                }
            }
        }
        for row in archive.workplaces {
            _ = try required(row, "name")
            guard (1...7).contains(try number(row, "weekStartWeekday")) else {
                throw CoufunchBackupError.invalidRecord("invalid weekday")
            }
            _ = try date(row, "createdAt")
        }
        for row in archive.paySettings {
            _ = try identifier(row, "workplaceID")
            guard PayCalculationMode(rawValue: try required(row, "payMode")) != nil else {
                throw CoufunchBackupError.invalidFile
            }
            _ = try optionalDecimal(row, "customHourlyRate")
            _ = try optionalDecimal(row, "fixedDailyPay")
            _ = try boolean(row, "nightPremiumEnabled")
            _ = try boolean(row, "overtimePremiumEnabled")
            _ = try date(row, "createdAt")
        }
        for row in archive.sessions {
            _ = try identifier(row, "workplaceID")
            let start = try date(row, "startAt")
            if let end = try optionalDate(row, "endAt"), end <= start {
                throw CoufunchBackupError.invalidRecord("session end before start")
            }
            guard WorkSessionStatus(rawValue: try required(row, "status")) != nil,
                  PayCalculationMode(rawValue: try required(row, "payMode")) != nil else {
                throw CoufunchBackupError.invalidFile
            }
            _ = try optionalDecimal(row, "hourlyRateSnapshot")
            _ = try optionalDecimal(row, "fixedDailyPaySnapshot")
            _ = try date(row, "recordedAt")
            _ = try optionalDate(row, "scheduledEndAt")
            _ = try optionalBoolean(row, "nightPremiumSnapshot")
            _ = try optionalBoolean(row, "overtimePremiumSnapshot")
        }
        for row in archive.breaks {
            _ = try identifier(row, "sessionID")
            guard try date(row, "endAt") > date(row, "startAt") else {
                throw CoufunchBackupError.invalidRecord("invalid break interval")
            }
        }
        for row in archive.rules {
            _ = try identifier(row, "workplaceID")
            _ = try required(row, "name")
            guard IncentivePeriod(rawValue: try required(row, "period")) != nil else {
                throw CoufunchBackupError.invalidFile
            }
            _ = try number(row, "requiredAttendanceDays")
            _ = try decimal(row, "amount")
            _ = try boolean(row, "canStack")
            _ = try boolean(row, "isEnabled")
        }
        for row in archive.incentives {
            _ = try identifier(row, "workplaceID")
            _ = try optionalIdentifier(row, "sessionID")
            _ = try date(row, "earnedOn")
            _ = try required(row, "name")
            _ = try decimal(row, "amount")
        }
        for row in archive.receipts {
            _ = try date(row, "monthStart")
            _ = try optionalIdentifier(row, "workplaceID")
            _ = try optionalIdentifier(row, "sessionID")
            guard BonusInclusion(rawValue: try required(row, "bonusInclusion")) != nil,
                  ReceivedPayBasis(rawValue: try required(row, "basis")) != nil else {
                throw CoufunchBackupError.invalidFile
            }
            _ = try decimal(row, "amount")
            _ = try optionalDecimal(row, "grossAmount")
            _ = try date(row, "createdAt")
            _ = try optionalDate(row, "depositedAt")
        }
    }

    /// Additive import: matching IDs are never modified or deleted.
    /// Preflight validation happens before any inserts; one save commits the entire import.
    @discardableResult
    static func restore(_ archive: CoufunchBackupArchive, into context: ModelContext) throws -> Int {
        try validate(archive)
        var added = 0
        var present = Set<UUID>()
        let existingWorkplaces = try context.fetch(FetchDescriptor<Workplace>())
        let existingSettings = try context.fetch(FetchDescriptor<WorkplacePaySettings>())
        let existingSessions = try context.fetch(FetchDescriptor<WorkSession>())
        let existingBreaks = try context.fetch(FetchDescriptor<WorkBreak>())
        let existingRules = try context.fetch(FetchDescriptor<IncentiveRule>())
        let existingIncentives = try context.fetch(FetchDescriptor<ManualIncentive>())
        let existingReceipts = try context.fetch(FetchDescriptor<ReceivedPayRecord>())
        for id in existingWorkplaces.map(\.id) + existingSettings.map(\.id) +
            existingSessions.map(\.id) + existingBreaks.map(\.id) +
            existingRules.map(\.id) + existingIncentives.map(\.id) +
            existingReceipts.map(\.id) { present.insert(id) }

        // Do not create dangling references to records missing both locally and in the archive.
        let workplaceIDs = Set(existingWorkplaces.map(\.id) + archive.workplaces.compactMap { UUID(uuidString: $0["id"] ?? "") })
        let sessionIDs = Set(existingSessions.map(\.id) + archive.sessions.compactMap { UUID(uuidString: $0["id"] ?? "") })
        for row in archive.paySettings + archive.sessions + archive.rules + archive.incentives {
            guard workplaceIDs.contains(try identifier(row, "workplaceID")) else {
                throw CoufunchBackupError.invalidRecord("missing referenced workplace")
            }
        }
        for row in archive.breaks {
            guard sessionIDs.contains(try identifier(row, "sessionID")) else {
                throw CoufunchBackupError.invalidRecord("missing referenced session")
            }
        }
        for row in archive.incentives + archive.receipts {
            if let sid = try optionalIdentifier(row, "sessionID"), !sessionIDs.contains(sid) {
                throw CoufunchBackupError.invalidRecord("missing referenced session")
            }
        }
        for row in archive.receipts {
            if let wid = try optionalIdentifier(row, "workplaceID"), !workplaceIDs.contains(wid) {
                throw CoufunchBackupError.invalidRecord("missing referenced workplace")
            }
        }

        func shouldInsert(_ row: [String: String]) throws -> Bool {
            let id = try identifier(row)
            guard !present.contains(id) else { return false }
            present.insert(id)
            added += 1
            return true
        }

        do {
            for row in archive.workplaces {
                guard try shouldInsert(row) else { continue }
                context.insert(Workplace(id: try identifier(row), name: try required(row, "name"),
                    weekStartWeekday: try number(row, "weekStartWeekday"),
                    createdAt: try date(row, "createdAt")))
            }
            for row in archive.paySettings {
                guard try shouldInsert(row) else { continue }
                let item = WorkplacePaySettings(
                    workplaceID: try identifier(row, "workplaceID"),
                    payMode: PayCalculationMode(rawValue: try required(row, "payMode"))!,
                    customHourlyRate: try optionalDecimal(row, "customHourlyRate"),
                    fixedDailyPay: try optionalDecimal(row, "fixedDailyPay"),
                    nightPremiumEnabled: try boolean(row, "nightPremiumEnabled"),
                    overtimePremiumEnabled: try boolean(row, "overtimePremiumEnabled"))
                item.id = try identifier(row)
                item.createdAt = try date(row, "createdAt")
                context.insert(item)
            }
            for row in archive.sessions {
                guard try shouldInsert(row) else { continue }
                context.insert(WorkSession(id: try identifier(row),
                    workplaceID: try identifier(row, "workplaceID"),
                    startAt: try date(row, "startAt"),
                    endAt: try optionalDate(row, "endAt"),
                    status: WorkSessionStatus(rawValue: try required(row, "status"))!,
                    payMode: PayCalculationMode(rawValue: try required(row, "payMode"))!,
                    hourlyRateSnapshot: try optionalDecimal(row, "hourlyRateSnapshot"),
                    fixedDailyPaySnapshot: try optionalDecimal(row, "fixedDailyPaySnapshot"),
                    recordedAt: try date(row, "recordedAt"),
                    scheduledEndAt: try optionalDate(row, "scheduledEndAt"),
                    nightPremiumSnapshot: try optionalBoolean(row, "nightPremiumSnapshot"),
                    overtimePremiumSnapshot: try optionalBoolean(row, "overtimePremiumSnapshot")))
            }
            for row in archive.breaks {
                guard try shouldInsert(row) else { continue }
                context.insert(WorkBreak(id: try identifier(row),
                    sessionID: try identifier(row, "sessionID"),
                    startAt: try date(row, "startAt"), endAt: try date(row, "endAt")))
            }
            for row in archive.rules {
                guard try shouldInsert(row) else { continue }
                context.insert(IncentiveRule(id: try identifier(row),
                    workplaceID: try identifier(row, "workplaceID"),
                    name: try required(row, "name"),
                    period: IncentivePeriod(rawValue: try required(row, "period"))!,
                    requiredAttendanceDays: try number(row, "requiredAttendanceDays"),
                    amount: try decimal(row, "amount"),
                    canStack: try boolean(row, "canStack"),
                    isEnabled: try boolean(row, "isEnabled")))
            }
            for row in archive.incentives {
                guard try shouldInsert(row) else { continue }
                context.insert(ManualIncentive(id: try identifier(row),
                    workplaceID: try identifier(row, "workplaceID"),
                    sessionID: try optionalIdentifier(row, "sessionID"),
                    earnedOn: try date(row, "earnedOn"),
                    name: try required(row, "name"), amount: try decimal(row, "amount")))
            }
            for row in archive.receipts {
                guard try shouldInsert(row) else { continue }
                let item = ReceivedPayRecord(id: try identifier(row),
                    monthStart: try date(row, "monthStart"),
                    workplaceID: try optionalIdentifier(row, "workplaceID"),
                    amount: try decimal(row, "amount"),
                    basis: ReceivedPayBasis(rawValue: try required(row, "basis"))!,
                    note: row["note"] ?? "",
                    sessionID: try optionalIdentifier(row, "sessionID"),
                    bonusInclusion: BonusInclusion(rawValue: try required(row, "bonusInclusion"))!,
                    depositedAt: try optionalDate(row, "depositedAt"),
                    allowanceAwardID: row["allowanceAwardID"].flatMap { $0.isEmpty ? nil : $0 },
                    includedBonusTypes: Set((row["includedBonusTypes"] ?? "").split(separator: ",").map(String.init)),
                    grossAmount: try optionalDecimal(row, "grossAmount"))
                item.createdAt = try date(row, "createdAt")
                context.insert(item)
            }
            try context.save()
            return added
        } catch {
            context.rollback()
            throw error
        }
    }
}

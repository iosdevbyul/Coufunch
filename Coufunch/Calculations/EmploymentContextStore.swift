import Foundation

/// Stable, local-only keys for employer-specific monthly screening answers.
/// The selected month is normalized in the supplied calendar; old global
/// answers are deliberately not migrated as they cannot be attributed safely.
enum EmploymentContextStore {
    static func monthKey(_ month: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month], from: month)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }

    static func key(workplaceID: UUID, month: Date, field: String, calendar: Calendar) -> String {
        "insurance.employment.\(workplaceID.uuidString).\(monthKey(month, calendar: calendar)).\(field)"
    }

    static func answer(_ raw: String?) -> Bool? {
        switch raw {
        case "yes": return true
        case "no": return false
        default: return nil
        }
    }

    static func previousMonthEmployment(
        workplaceID: UUID, month: Date, calendar: Calendar, defaults: UserDefaults = .standard
    ) -> Bool? {
        answer(defaults.string(forKey: key(
            workplaceID: workplaceID, month: month,
            field: "previousMonth", calendar: calendar
        )))
    }

    static func startedOnFirstDay(
        workplaceID: UUID, month: Date, calendar: Calendar, defaults: UserDefaults = .standard
    ) -> Bool? {
        answer(defaults.string(forKey: key(
            workplaceID: workplaceID, month: month,
            field: "startedOnFirstDay", calendar: calendar
        )))
    }
}

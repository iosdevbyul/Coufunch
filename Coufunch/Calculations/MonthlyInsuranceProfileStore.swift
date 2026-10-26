import Foundation

/// Separate, locally stored insurance settings for a single employer and month.
/// Legacy global preferences are deliberately not migrated or used as fallback.
enum MonthlyInsuranceProfileStore {
    enum Field: String {
        case pensionEnrollment
        case healthEnrollment
        case pensionBase
        case healthBase
    }

    static func key(
        workplaceID: UUID, month: Date, field: Field, calendar: Calendar
    ) -> String {
        "insurance.profile.\(workplaceID.uuidString).\(EmploymentContextStore.monthKey(month, calendar: calendar)).\(field.rawValue)"
    }

    static func raw(
        workplaceID: UUID, month: Date, field: Field,
        calendar: Calendar, defaults: UserDefaults = .standard
    ) -> String? {
        defaults.string(forKey: key(
            workplaceID: workplaceID, month: month, field: field, calendar: calendar
        ))
    }

    static func enrollment(
        workplaceID: UUID, month: Date, field: Field,
        calendar: Calendar, defaults: UserDefaults = .standard
    ) -> InsuranceEnrollment {
        switch raw(workplaceID: workplaceID, month: month, field: field,
                   calendar: calendar, defaults: defaults) {
        case "enrolled": return .enrolled
        case "notEnrolled": return .notEnrolled
        default: return .unknown
        }
    }

    static func contributionBase(
        workplaceID: UUID, month: Date, field: Field,
        calendar: Calendar, defaults: UserDefaults = .standard
    ) -> Decimal? {
        guard let raw = raw(workplaceID: workplaceID, month: month, field: field,
                            calendar: calendar, defaults: defaults),
              !raw.isEmpty, let value = Decimal(string: raw), value >= 0 else {
            return nil
        }
        return value
    }
}

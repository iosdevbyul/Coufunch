import Foundation

struct MonthlyHealthEligibilityResult {
    let attendanceDays: Int
    let screening: InsuranceEnrollment
}

/// An informational screening for one workplace and one calendar month.
/// Employment continuity is externally confirmed; shift history alone does
/// not prove enrollment or employer-reported insurance qualification.
enum MonthlyHealthEligibilityScreening {
    static func evaluate(
        month: Date,
        workplaceID: UUID,
        sessions: [WorkSession],
        employedPreviousMonth: Bool?,
        startedOnFirstDay: Bool?,
        calendar: Calendar
    ) -> MonthlyHealthEligibilityResult {
        guard let interval = calendar.dateInterval(of: .month, for: month) else {
            return MonthlyHealthEligibilityResult(attendanceDays: 0, screening: .unknown)
        }
        let attendance = WorkAttendance.uniqueDays(
            of: sessions, workplaceID: workplaceID, calendar: calendar
        ).filter { interval.contains($0) }
        let screening = DailyWorkerHealthEligibility.evaluate(
            DailyWorkerInsuranceContext(
                month: month,
                attendanceDays: attendance.count,
                employedPreviousMonth: employedPreviousMonth,
                startedOnFirstDay: startedOnFirstDay
            )
        )
        return MonthlyHealthEligibilityResult(
            attendanceDays: attendance.count, screening: screening
        )
    }
}

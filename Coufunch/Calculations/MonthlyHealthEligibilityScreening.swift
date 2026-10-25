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
        // Insurance attendance differs from bonus-qualified attendance:
        // a completed early-departure shift still represents a worked day.
        let attendance = Set(sessions.filter {
            $0.workplaceID == workplaceID && $0.status == .completed &&
            interval.contains($0.startAt)
        }.map { calendar.startOfDay(for: $0.startAt) })
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

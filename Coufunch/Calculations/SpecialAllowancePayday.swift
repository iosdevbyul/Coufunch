import Foundation

/// Six-attendance-day weekly special allowance is expected on the Tuesday
/// immediately following the qualifying workweek. This is not the next
/// business day after the last shift, and is not shifted for holidays.
enum SpecialAllowancePayday {
    static func followingTuesday(weekStart: Date, calendar baseCalendar: Calendar) -> Date? {
        var calendar = baseCalendar
        guard let week = calendar.dateInterval(of: .weekOfYear, for: weekStart),
              let nextWeekStart = calendar.date(byAdding: .day, value: 7, to: week.start) else {
            return nil
        }
        let weekday = calendar.component(.weekday, from: nextWeekStart)
        let daysUntilTuesday = (3 - weekday + 7) % 7
        guard let tuesday = calendar.date(byAdding: .day, value: daysUntilTuesday,
                                          to: nextWeekStart) else { return nil }
        return calendar.date(bySettingHour: 10, minute: 0, second: 0, of: tuesday)
    }

    static func dueDates(sessions: [WorkSession], workplaces: [Workplace],
                         rules: [IncentiveRule], calendar baseCalendar: Calendar) -> [Date] {
        var result: [Date] = []
        for workplace in workplaces {
            var calendar = baseCalendar
            calendar.firstWeekday = workplace.weekStartWeekday
            let awards = WorkIncentiveCalculator.awards(
                sessions: sessions, rules: rules, workplace: workplace, calendar: calendar)
            for award in awards {
                guard rules.contains(where: {
                    $0.id == award.ruleID && $0.period == .weekly &&
                    $0.requiredAttendanceDays == 6
                }), let due = followingTuesday(weekStart: award.periodStart, calendar: calendar)
                else { continue }
                result.append(due)
            }
        }
        return result
    }
}

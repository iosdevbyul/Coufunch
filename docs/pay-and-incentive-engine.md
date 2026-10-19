# Pay and incentive engine (Phase 3)

Pure calculation layer for Coufunch. No changes to existing SwiftUI views or the WakTrainerDesignSystem theme.

## Inputs

- WorkSession with an explicit wage snapshot
- Zero or more WorkBreak intervals, all bounded within the shift
- A timezone-aware Calendar for civil-day / 22:00–06:00 interpretation
- Per-workplace attendance and incentive rules

## Gross pay

- Hours outside night window are paid at the supplied hourly rate.
- Night hours 22:00–06:00 (local civil time) receive an additional 50% of hourly rate, when enabled.
- Break intervals are excluded. Overlapping breaks are combined before subtraction.
- A fixed daily wage overrides all calculated hourly wage or night premiums.
- Rates and fixed wages are stored as Decimal inputs; computed outputs are Decimal.
- 5-minute snapped timeline selection is a future UI task; the calculation API accepts arbitrary Date timestamps and rounds elapsed minute counts. Do not treat input rounding as a UI validation substitute.
- Gross figures exclude taxes, insurance and deductions; overtime, holiday premiums, statutory eligibility, payroll rounding and irregular legal conditions are out of scope.

## Incentives

- Attendance uses unique *start dates* per workplace, from **completed** sessions only.
- Weekly periods use the workplace-configured first weekday; monthly periods use local calendar months.
- Threshold incentives award once per qualifying calendar period.
- Stackable rules are summed. Nonstackable rules with the same period and period start compete; only the highest is awarded.
- Manual incentives remain separate and never affect threshold attendance.
- No hard-coded workplace names or Coufunch-specific employer presets live in the engine.

## Important integration constraints

- WorkSession with no end date or absent wage snapshot does not silently receive an estimated wage.
- Always pass the effective local timezone and an explicit applicable minimum hourly rate captured at the time of work.
- The current model is a foundational model: UI editing and persisted rule exception/override states will be added separately.
- For monthly payment views, establish a payout attribution policy for a weekly incentive whose qualifying Sunday–Saturday week crosses the month boundary. This version returns the *period start* to let the UI apply the agreed policy later.
- iOS Simulator tests are run by the PR CI workflow. Do not merge when red.

# Payroll validation matrix (PR #14)

## Automated checks
- Multiple unpaid breaks across midnight; worked and nighttime minutes are calculated separately.
- Overlapping break records are unioned before subtracting paid time; the same minute is not deducted twice.
- Breaks outside a shift are rejected instead of silently altering gross pay.
- December 31, 2026 / January 1, 2027 minimum wage rate selection: KRW 10,320 / KRW 10,700; an unknown year returns nil.
- Shifts spanning midnight count as an attendance day on their start date.
- Previously recorded wage and premium-setting snapshots survive changes to workplace defaults in the same in-memory data store.
- Existing tests cover 1–2 hours of daily overtime, nighttime + overtime premium overlap, fixed daily pay, forecast statuses and incentive thresholds.

## Validation still required on a real device or with actual pay evidence
- Use real iPhone touch interactions to check horizontal scrolling, shift handles, 5-minute adjustment buttons, multiple break edits, Dynamic Type and VoiceOver.
- Compare actual shift start/end, multiple unpaid breaks, wage and bonus breakdowns with genuine employer payslips.
- Check gross estimated versus **gross received**, not net cash deposits.
- Existing installed SwiftData store migration across app updates is **not** proved by the in-memory store test above. An upgrade test using a prior app build and pre-existing local records is needed.

## Deliberate exclusions
- Do not add weekly 40-hour overtime rules.
- No invented employer eligibility, withholding, holiday premium or final net pay calculations.
- No claim that a scenario test proves actual wage payment correctness.

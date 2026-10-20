# Real-device payroll validation checklist

This is a verification plan, not a claim of real-device or employer-payment validation.

## On an iPhone
1. Open a work session for a selected date. Scroll the ruler across midnight; adjust shift start/end with handles and five-minute buttons.
2. Create, move, and remove two breaks. Confirm they do not overlap and both lower paid minutes.
3. Reopen a saved session. Confirm time, breaks, status, hourly-rate snapshot, and premium settings survived an app restart.
4. Increase Dynamic Type, use VoiceOver, and try a narrow screen. Note any clipped action labels or unusable drag handles.

## Payslip comparison
1. Enter actual start/end, unpaid break intervals, wage mode, employer premium eligibility, and incentive conditions.
2. Compare **Payroll Audit** per-shift base pay, night and daily overtime premium against gross payroll line items.
3. Compare monthly automatic/manual incentives separately; never compare net deposit directly with gross estimated pay.
4. Record discrepancies as reproducible cases. Do not claim legal compliance from matching one payslip.

## Data continuity
- The included on-disk test checks closing and reopening a store with an unchanged schema.
- Upgrading a populated database from a **prior app release/schema** is a separate manual test: create records in the previous build, replace app without uninstalling, and check every record and attachment survives.
- Do not delete/reinstall the app for migration testing, because uninstall may delete local data.

## Excluded
Weekly 40-hour overtime calculations are intentionally excluded.

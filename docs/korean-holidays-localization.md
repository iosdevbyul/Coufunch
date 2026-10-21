# Korean public holidays, premium calculations and localization

## Current implementation
- Cached yearly Korean public holiday dates are retrieved from Nager.Date's KR PublicHolidays API when the app is online.
- Only entries marked `Public` are treated as public holidays. No weekend is automatically treated as a statutory public holiday.
- Paid time on a holiday excludes overlapping unpaid breaks and supports shifts crossing midnight.
- For eligible hourly-paid work, the holiday premium is +50% for the first eight holiday paid hours and +100% for the remaining holiday paid hours. Duplicate daily overtime premium is removed for those same holiday hours.
- Day-rate/fixed-pay sessions are not automatically increased by this calculator.
- Monthly summary, forecast, shift audit and CSV receive the same holiday date set.
- Korean localization catalog begins with the principal UI labels; English remains the source language.

## Important limitations before relying on payroll numbers
- Nager.Date is an independent data provider, not the Korean government's authoritative paid-holiday entitlement service. Verify replacement holidays and newly declared holidays against official Korean notices.
- The external provider could be unavailable or incomplete. In that case, current cached dates are used, or holiday pay could be omitted; never interpret a missing network result as proof that a day is not a holiday.
- A public holiday is not necessarily a paid holiday under every employer contract. Workplace eligibility, substituted holidays and separate paid holiday allowances require employer-specific checks.
- Holiday dates have not been persisted as historical per-session entitlements. Old estimates may vary when public holiday data changes.
- Full-screen Korean translation remains to be completed, including dynamic text and package-provided UI.
- Calendar weekday header colors require TrisCalendarKit PR #2 merged and a new tagged release. This app deliberately stays pinned to a release rather than the package's moving branch.

## Follow-ups
1. Verify holiday data quality and add an official Korean government fallback or auditable curated yearly calendar.
2. Add employer-specific holiday eligibility and holiday snapshot storage.
3. Complete Korean translations for all app screens and test iOS per-app language selection.
4. Release TrisCalendarKit's configurable weekday colors, pin the tagged version in Coufunch and set Saturday blue / Sunday red only for the weekday header labels.
5. Run full CI and iPhone UI/payroll regression tests. No weekly 40-hour overtime rule.

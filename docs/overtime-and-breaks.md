# Work session overtime and break editor

## Eligibility and scope

The estimate uses the 2026 Korean Labor Standards Act (Article 56) for establishments where the statutory 50% premium applies (generally at least five regular employees). A worker's contract, exceptions, flexible schedules, and holiday rules can change the actual amount. This is **gross estimated pay**, not payroll or legal determination.

- Base pay: hourly rate × all paid minutes.
- Night premium: 50% hourly rate × paid minutes from 22:00 to 06:00.
- Daily overtime premium: 50% hourly rate × paid minutes over 8 hours in the same continuous session, excluding unpaid breaks.
- If night and overtime overlap, both additional premiums are added; base pay is counted once.
- Fixed daily pay is preserved as entered and no premium is automatically added to prevent double counting.
- The calculator has `nightPremiumEnabled` and `overtimePremiumEnabled` flags. The latter defaults to true in this phase. A workplace-level eligibility control is not yet modeled; verify eligibility before treating projections as payroll.
- For multiple sessions on a day, this phase does not aggregate paid hours across sessions into daily overtime. The result can underestimate premiums.
- Weekly-hours overtime calculations are intentionally not part of Coufunch. Holiday work and higher contractual premiums also are not calculated.

## Timeline

- A shared horizontally scrolling 48-hour ruler remains in use.
- Multiple breaks can be added, selected and removed; one selected break at a time is edited on the shared break lane.
- All breaks are recorded and excluded from paid hours by the calculation engine.
- The view now displays the pay breakdown as the working range is changed.

## Testing

- Two hours overtime after an eight-hour paid shift.
- Overlapping nighttime and overtime premiums.
- Fixed daily wage without accidental double pay.
- Ability to disable overtime premium for an ineligible workplace.

Manual device validation remains essential for scroll vs drag interactions and accessibility.

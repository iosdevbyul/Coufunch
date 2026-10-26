# Final iPhone acceptance: Coufunch

This is an acceptance plan, **not** a claim that real-device tests or real employer-pay reconciliation have passed. Complete it only after all related PRs have merged and CI is green.

## Prerequisites

- Confirm no open PRs and latest `main` CI passes.
- Preserve any unrelated local changes and saved stashes; do not discard localizations or user data.
- From a clean working tree: `git switch main && git pull --ff-only origin main && xcodegen generate`.
- Record iPhone model, iOS version, app commit SHA and test date. Use a real device for notification and accessibility checks.

## Acceptance checklist

| ID | Scenario | Evidence to collect |
| --- | --- | --- |
| A01 | Install fresh on iPhone; home screen shows intended Coufunch icon | Screenshot; verify installed icon uses multi-size AppIcon catalog |
| A02 | Configure workplace and custom/flat wage; add, edit and reopen a shift | Saved rates and session dates; screenshots |
| A03 | Overnight shift with two breaks and early departure at minute precision | Worked minutes, wages and premium breakdown |
| A04 | Sunday–Saturday 5- and 6-day attendance bonuses and monthly 15-day incentive | Expected thresholds, weekly start-day preference, earned period vs deposit dates |
| A05 | Compare monthly gross, estimated employee insurance deductions and actual receipts | Separate gross estimates, net receipts, insurance eligibility, unknown values; never force equality |
| A06 | Browse known holidays including substitutes and restart without network | Date labels, offline cache behavior, missing-year fallback |
| A07 | Ordinary next-business-day payday notification at **14:00 Asia/Seoul** | Notification permission, date/time and Korean text “오늘은 급여일입니다.” |
| A08 | Six-day special-allowance reminder at **10:00 Asia/Seoul** | Verify it remains independent even when both reminders occur same day |
| A09 | Switch device language to Korean; check screens, payroll help and alert copy | No accidental English user-facing guidance |
| A10 | Test small iPhone, large Dynamic Type and VoiceOver | Buttons, drag handles, labels, reading order |
| A11 | Install updated build **over** a previous populated build without uninstalling | Retained shifts, receipts, wage snapshots, incentives and settings |

## Failure criteria and follow-up

Mark the case **Pass**, **Fail**, or **Not Tested**. Record clear reproduction steps, expected/actual values, affected device/iOS and redacted screenshots. Do not merge any corrective PR until its CI succeeds. Never mark an unperformed manual test as verified.

Existing automation exercises many payroll and date edge cases but does not establish real payroll accuracy, notification delivery, or historical schema migration. Weekly 40-hour overtime is not implemented.

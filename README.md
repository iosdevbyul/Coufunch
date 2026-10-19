# Coufunch

Coufunch is a SwiftUI iPhone app for managing work sessions, pay and incentives across workplaces.

## Current status

Phase 1: iOS project bootstrap. The monthly calendar and navigation are UI scaffolds; pay calculation, persistence, shift editing and onboarding are not yet implemented.

## Requirements and setup

- Xcode with Swift 6.3 support (TrisCalendarKit currently declares swift-tools-version 6.3)
- iOS 17 or later
- XcodeGen: `brew install xcodegen`

```sh
git clone https://github.com/iosdevbyul/Coufunch.git
cd Coufunch
xcodegen generate
open Coufunch.xcodeproj
```

Select the Coufunch scheme and run on an iPhone simulator.

## Confirmed product design

- Home: Work Overview calendar from TrisCalendarKit, week starts on Sunday, hamburger sidebar, refresh.
- Workplaces are named manually by the user; multiple work sessions can begin on the same date.
- Each session belongs to its start date, including overnight sessions.
- Hourly pay may use minimum wage or a custom rate; alternatively a flat daily wage may be entered.
- Night premiums use working minutes between 22:00 and 06:00, excluding break periods where applicable.
- Time ranges are selected by dragging on a horizontally scrollable timeline with 5-minute snapping.
- Workplace-specific weekly/monthly incentive rules, editable presets, manual awards, and no-incentive setup.
- Payslips show estimates before insurance and tax deductions.
- Original inputs for historical work records are preserved when workplace defaults change.

## Development workflow

Feature branch → code → build/test → commit → push → PR → CI → merge. Do not commit directly to main.

## Phase 1 files

`project.yml` defines the XcodeGen-generated project, targets and versioned TrisCalendarKit dependency. `.github/workflows/ci.yml` generates and builds for iOS Simulator on pull requests. The initial app view is a calendar/sidebar shell; the refresh control currently returns to the current month.

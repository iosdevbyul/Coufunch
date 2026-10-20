# Coufunch iPhone upgrade and payroll verification

## Scope of automated tests
- Persist and reopen the current full SwiftData schema on disk with workplace preferences, a completed shift, breaks, incentive rules, a manual incentive and gross/net receipt data.
- Ensure editing a historical shift retains its recorded minimum-hourly wage snapshot instead of substituting the wage for the edited calendar date.
- These automated checks do **not** demonstrate migration from an earlier model schema.

## Physical iPhone checklist
1. Install a tagged/prior build without deleting the app. Add a workplace, several shifts (including an overnight shift), two breaks, an incentive and a payment receipt. Record the displayed values.
2. Install the new build **over the previous install**. Do not uninstall or clear application storage.
3. Reopen the same records and confirm IDs, wage snapshots, premium toggles, breaks, incentives and payment receipts are intact. Edit one historical shift and verify its original hourly wage snapshot is retained.
4. In the timeline, swipe the ruler, drag handles, use each five-minute control and confirm break intervals cannot overlap. Check VoiceOver, Dynamic Type and compact width.
5. Compare the Payroll Audit against a real gross payslip, separating base pay, night premium, daily overtime premium and bonuses. Net deposits cannot be compared directly with estimated gross.

## Evidence and sign-off
Record device model/iOS version, prior app version and updated app version, whether the install retained user data, input shifts and gross payslip line items, observed differences and screenshots (redact personal data).

If any of these steps have not been performed, mark physical-device, prior-version schema migration and real-payroll verification as **not verified**.

Weekly 40-hour overtime calculations are outside Coufunch's scope.

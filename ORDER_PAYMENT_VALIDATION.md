# Automatic payment statuses and due dates

Signing forms offer Automatic, Paid, and Cancelled. Automatic sends `paid: false`
and `paymentStatus: "Scheduled"`; it never sends the UI label "Automatic".
Cancelled clears Paid and paid date. Paid supports the existing optional paid
date, including reopening a paid order that has no paid date.

Create and edit forms provide an optional Payment due date picker and Clear
action. Calendar dates stay as `YYYY-MM-DD` strings. The picker converts only
between a local calendar day and its local display value; due dates never pass
through timestamp or UTC-to-local conversion. Save payloads omit unchanged due
dates, send a new date when edited, and send null when cleared.

Order decoding prioritizes the API's `paymentStatus` over legacy `status`.
Badges, filters, collected revenue, and unpaid eligibility use that effective
status. Only legacy responses without a status and the debug mock calculate
statuses locally: Cancelled, then Paid, then Overdue after the due date, then
Pending after the signing date, otherwise Scheduled. Boundaries use UTC days.
There is no automatic Overdue state without a due date, and Pending does not
confirm signing completion.

The app refreshes orders after every signing-form save, whenever the foreground
scene becomes active, and at the next UTC midnight while active. The timer is
cancelled in the background and on account changes. Save responses update the
ledger immediately, and refresh failure retains that saved response. Revision
and account checks prevent older refreshes from replacing a newer saved order.

The debug API now retains created and edited orders, preserves omitted due
dates, accepts null for clearing, validates date-only due dates, and recalculates
payment statuses on every read and write.

## Verification

`OrderPaymentTests` covers UTC midnight, due-today boundaries, absent due dates,
Paid/Cancelled precedence, date round trips in four time zones, payload
preservation and clearing, optional paid dates, server-status totals, and mock
creation/editing/extension/clearing/rescheduling. `ValidationAndAPITests` covers
order refresh and retention of saved data on refresh failure.

UI tests exercise creating a signing with a due date and no paid date, loading
and clearing a saved due date, reopening the picker, all three status controls,
saved status updates, and the Dashboard's filtered unpaid list.

Use `notaryledger-ios.xcodeproj`, scheme `notaryledger-ios-Stripe`, with the
installed iPhone simulator. The production compile check uses Release,
`SWIFT_ACTIVE_COMPILATION_CONDITIONS=PRODUCTION`, a generic iOS destination, and
`CODE_SIGNING_ALLOWED=NO`; it does not archive, sign, or publish an app.

No project lint configuration or SwiftLint installation exists. The new payment
modules and tests are checked with strict `swift-format lint`, four-space
indentation and 140-character line length; `git diff --check` covers all edits.

Verified: 49 payment/model/dashboard/payload tests, 69 API and refresh tests,
and all three focused UI tests passed. Strict lint, diff checks, and the
production-configured iOS Release build passed.

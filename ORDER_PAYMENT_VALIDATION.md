# Automatic payment statuses and due dates

Signing forms offer Automatic, Paid, and Cancelled. Automatic sends `paid: false`
and `paymentStatus: "Scheduled"`; it never sends the UI label "Automatic".
Cancelled clears Paid and paid date. Paid supports the existing optional paid
date, including reopening a paid order that has no paid date.

Profile provides a one-time Default payment due (days) setting, from 0 through
365 days after each signing. Zero means the signing day; blank removes the
default. The preference persists per account on this device because the current
profile API has no payment-terms setting. It survives sign-out and app restart,
and one account's preference does not affect another account.

Signing create/edit/detail screens have no due-date picker, field, or toggle.
The shared creation API applies the saved number of days to the signing's UTC
calendar date and sends the resulting `YYYY-MM-DD` due date. This includes
manual creation and reviewed screenshot/PDF entries. Existing order edits omit
dueDate and preserve its saved value, including when the Profile default changes.
The underlying payload still supports explicit date/null operations for API
compatibility.

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

Spreadsheet imports apply the default to newly saved orders that do not already
have a due date, using the supported order update endpoint. Required fields,
timestamps, paid dates, and structured mileage are preserved. If a follow-up due
date update fails, the imported orders remain available and the import summary
reports how many payment deadlines could not be saved.

## Verification

`OrderPaymentTests` covers UTC midnight, due-today boundaries, absent due dates,
Paid/Cancelled precedence, date round trips in four time zones, payload
preservation and clearing, optional paid dates, server-status totals, and mock
creation/editing/extension/clearing/rescheduling. `ValidationAndAPITests` covers
order refresh and retention of saved data on refresh failure.

`PaymentTermsDefaultsTests` covers account-scoped persistence and clearing,
whole-day validation, same-day terms, UTC offsets, month and leap-year boundaries,
creation payloads, edit preservation, imports, and partial import-update failure.
UI tests exercise saving the Profile default, persistence across app relaunch,
creating/editing signings without due-date controls, all three status controls,
and optional paid dates. The Dashboard's filtered unpaid list remains covered.

Use `notaryledger-ios.xcodeproj`, scheme `notaryledger-ios-Stripe`, with the
installed iPhone simulator. The production compile check uses Release,
`SWIFT_ACTIVE_COMPILATION_CONDITIONS=PRODUCTION`, a generic iOS destination, and
`CODE_SIGNING_ALLOWED=NO`; it does not archive, sign, or publish an app.

No project lint configuration or SwiftLint installation exists. The new payment
modules and tests are checked with strict `swift-format lint`, four-space
indentation and 140-character line length; `git diff --check` covers all edits.

The Profile-default change is verified with 123 focused unit/API tests and the
Profile/signing UI checks, strict lint of the new settings code/tests, diff
checks, and the production-configured iOS Release build.

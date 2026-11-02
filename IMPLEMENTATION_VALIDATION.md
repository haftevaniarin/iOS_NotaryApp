Implementation and local validation — November 1, 2026

The native SwiftUI app retains its parchment, navy, and brass components. Implementations in the web source and backend route/service files were used as the contracts. No applicable AGENTS.md files were found in the project directories or their ancestors.

The app project is `test/notaryledger-ios.xcodeproj`, relative to `/Users/arin/test`; its scheme is `notaryledger-ios`, module `notaryledger_ios`, and bundle ID `org.notaryledger.ios`. The outer `test.xcodeproj` is a separate wrapper and was not used for validation. The git repository is `/Users/arin/test/test`.

Implemented behavior:

- Profile: one initials/photo avatar acts as the Photos picker and preview. Supported JPEG, PNG, and WebP images are validated against the 5 MB limit. Upload, replacement, removal, asynchronous scan status, rejection, cancellation, bounded retry of transient scan-status errors, and restoring pending uploads use the existing photo routes. Default start address loads and saves through `/api/auth/me` and prepopulates mileage entry.
- Credentials: commission, E&O, background check, and certification fields load and save real backend records. Optional fields clear with JSON null; decimal coverage amounts decode correctly. Calendar dates are normalized for editing. Expiration reminders use the web app's calendar-month window and now drive dashboard banners. The unsupported standalone bond-expiration field was removed.
- Business cards: native editing includes the backend-supported identity, biography, location, service areas, languages, phone/email, social links, image URLs, and profile-photo opt-in. Field validation, explicit phone/email visibility, draft saving, publishing/unpublishing, canonical-link sharing, and backend-generated public vCard sharing are supported. Unsaved edits cannot be published or shared as if saved.
- Signing extraction: image/PDF uploads call `/api/orders/extract`, unwrap `data.draft`, and open the existing editable signing form. Only Save creates an order. Missing extraction values stay editable; failures do not create entries.
- Spreadsheet imports: CSV, TSV, and TXT exports up to 5 MB can be reviewed and edited before invoking `/api/orders/import`. The server remains responsible for header aliases, row validation, duplicate detection, atomic saving, and plan limits. Row errors and actual imported/skipped counts are shown.
- Data export: the authenticated JSON export response is validated, written to a protected temporary file, and presented through the native share sheet, including Save to Files. The response bytes are preserved rather than discarded.
- Account deletion: current backend status, requested date, scheduled date, request submission, and cancellation are restored and displayed. Request/cancel operations require the expected returned status before displaying success.
- Admin audit: real paginated records, an exact action filter, loading/errors, and record outcome/severity replace the samples. Only an exact ADMIN role enables navigation and loading; the backend also enforces authorization.
- Billing: real status/entitlements, monthly/annual checkout, browser portal access, confirmed checkout synchronization, scheduled interval changes, and cancellation of scheduled changes replace preview states. Checkout state is scoped to the signed-in account. Opening checkout does not grant Pro access.
- Mileage: nested backend summaries decode correctly. Manual/calculated one-way mileage, round trips, addresses, parking/tolls, route calculation, clearing, and bounded numeric validation use the backend field names. Ordinary signing edits preserve existing structured mileage and its precision. Date and time encode together, and payment status uses `paymentStatus`.
- Expenses: current backend categories, business-use percentages, image receipt extraction/review, and signing-specific expense CRUD are supported. Signing-specific requests omit the unsupported general-expense business-use field.
- Invoices: single-signing, customer, and custom invoices produce actual paginated shareable PDFs. Backend invoice entitlements are checked first. This follows the web's local PDF generation and does not create a Stripe invoice or email a customer.
- Tax summaries: decode `/api/reports/tax-summary` totals, including selected-year business miles, travel expenses, SE taxable income, and estimated payments. PDF exports use those authoritative totals. Estimated payment CRUD is available. Backend failures no longer silently substitute a different local calculation.
- Session/API handling: native login/refresh/logout use cookie-free requests and Keychain refresh tokens; refresh rotation is coalesced and an authenticated request retries once after a 401. Transient launch failures preserve the stored session. Named response envelopes and decimal strings decode correctly; backend field and spreadsheet-row errors remain visible. Required identifiers are not fabricated from malformed responses.

Validation completed:

- Debug build and tests passed on iPhone 17 Pro, iOS 26.1: 42 Swift Testing tests across three suites, plus one XCTest UI smoke test.
- Tests cover envelope decoding, profile persistence, admin role boundaries, credential clearing/decimals/expiration, card validation/privacy payloads, billing shapes, structured mileage, preserving mileage on ordinary edits, tax totals, deletion/audit wrappers, extraction draft shapes and failures, multipart requests, spreadsheet imports and duplicate counts, native token rotation/retry, export byte preservation, and PDF validity/pagination.
- UI smoke test passed login validation and recovery navigation. Its screenshot was exported and inspected at `/Users/arin/test/validation-artifacts/1D8D7798-DE0D-4830-BA99-B193D5FA2BFF.png`.
- Release simulator build passed.
- Selected existing web reference tests passed: 23 tests covering profile photos, invoices, payloads, and business-card models.
- Selected existing backend unit tests passed: 19 tests covering mileage, business cards, photo errors, and signing/receipt extraction providers. Database-backed route suites were not run against the configured database.
- `git diff --check` passed. Xcode emitted non-fatal AppIntents metadata and simulator-diagnostics collection messages; test execution and both build configurations succeeded.

Validation commands used Xcode per process, without changing the system developer-directory setting:

```sh
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project test/notaryledger-ios.xcodeproj -scheme notaryledger-ios \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=000113BD-CC07-4705-ACFB-6C07ACEA7151' \
  -derivedDataPath /Users/arin/test/.derived-data-parity \
  CODE_SIGN_IDENTITY=- -parallel-testing-enabled NO test
```

The equivalent Release check used `-configuration Release -destination 'generic/platform=iOS Simulator' build` and a separate derived-data directory. Local ad-hoc signing was required for simulator Keychain tests; the unsigned run could not persist native credentials.

Configuration and remaining verification:

| Configuration | Existing API selection |
| --- | --- |
| Debug | `STAGING`: `https://api-stage.notaryledger.org` |
| Release without an explicit environment flag | `.local`: `http://localhost:4000` |
| Explicit `PRODUCTION` flag | `https://notaryledger.org` |

APIConfig and production/build-environment settings were left unchanged. Release therefore still needs an explicitly chosen API environment before distribution. Existing cookie-only sessions need a one-time sign-in to acquire the new native refresh token.

The requested core routes exist; no new backend endpoint was invented. Live end-to-end validation still requires an authenticated test account, an isolated test database, enabled photo storage/scanning, configured extraction/routing providers, and Stripe test configuration. Actual photo storage, publishing a live card, charging/changing a subscription, deleting an account, and provider-backed extraction were not exercised against deployed services. Authenticated screen interactions and hardware-device behavior remain unverified beyond model/transport tests and simulator compilation.

No TestFlight/App Store publication, push, or production-configuration change was performed.

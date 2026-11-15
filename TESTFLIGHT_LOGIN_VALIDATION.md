# TestFlight login connectivity verification

Verified November 15, 2026.

## Root cause and selected URLs

The parent `../test.xcodeproj` builds the TestFlight staging app, scheme
`NotaryLedger`, bundle ID `org.notaryledger.app.staging`, version `1.0.0 (1)`.
The project defined `DEBUG STAGING` only in Debug. Release had neither `STAGING`
nor `PRODUCTION`, so `APIConfig.environment` fell through to `.local`.
Its Archive action uses Release. The checked source and resolved pre-fix Release
settings explain the reported simulator/device difference; the old uploaded IPA
was not independently extracted.

| Build | Before | After |
| --- | --- | --- |
| Staging Debug | `https://api-stage.notaryledger.org` | `https://api-stage.notaryledger.org` |
| Staging Release / Archive | `http://localhost:4000` | `https://api-stage.notaryledger.org` |
| Explicit `PRODUCTION` | `https://notaryledger.org` | unchanged |

The fixed staging login request is:

`POST https://api-stage.notaryledger.org/api/auth/login`

The origin has no `/api` suffix; the request supplies `/api/auth/login` once.
Tests cover both a trailing slash on the origin and a missing leading slash on
the route. No old Render hostname or emulator address was found in app settings
or source. The local origin remains available to the separate development
project; it is not selected by the staging app.

## Configuration and security

- Both staging app target configurations explicitly define
  `$(inherited) STAGING STAGING_APP`.
- `APIConfig.swift` rejects `STAGING_APP` without `STAGING` or with `PRODUCTION`.
  API environment selection does not depend on `DEBUG`.
- No xcconfig files or base configuration references were present. The shared
  staging scheme archives Release and launches Debug; neither overrides the URL.
- The separate `notaryledger-ios.xcodeproj` has bundle ID `org.notaryledger.ios`;
  its settings and the explicit production URL are unchanged. This checkout has
  no separately configured production app target.
- The generated staging Release Info.plist has no `NSAppTransportSecurity`
  exceptions. The separate project's custom `NotaryLedger-Info.plist` likewise
  has none. URLSession uses standard TLS validation; no trust bypass was found
  or added. No ATS exceptions are needed for the staging HTTPS origin.
- Backend authentication, CSRF, cookie behavior, and production resources were
  not modified.

The parent Xcode project is outside the Git repository rooted in this directory.
Its two build-setting edits are also preserved in
`scripts/staging-target-environment.patch`. If transferring only this Git repo,
apply that patch from the containing workspace directory with
`patch -p1 < test/scripts/staging-target-environment.patch` when the directory
layout matches this workspace. Do not omit the parent project change from the
next archive.

## Login diagnostics

The login request uses OSLog category `Login`, subsystem
`org.notaryledger.network`, at notice level in Debug and Release. Events include
the API hostname, fixed `/api/auth/login` path, HTTP status, and numeric
NSURLErrorDomain code. A zero status/code means that field is absent for the
event. HTTP response events precede JSON/session validation events.

Request/response bodies, headers, email addresses, URL queries, raw error
descriptions, credentials, tokens, and cookies are excluded from these logs.
The previous Debug body/error logging is skipped for login too.

Staging login errors display a separate support code while retaining the
user-facing error message:

| Code | Meaning |
| --- | --- |
| `NL-NET-1004` | Cannot connect to host |
| `NL-NET-1003` | Host lookup failed |
| `NL-NET-1001` | Timeout |
| `NL-NET-1009` | Offline |
| `NL-NET-1200` through `NL-NET-1206` | TLS/certificate failure |
| `NL-NET-1022` | ATS rejected the connection |
| `NL-NET` | Transport failure outside NSURLErrorDomain |
| `NL-HTTP-401` / `NL-HTTP-403` | Server rejected login / access |
| `NL-HTTP-500` / other `5xx` | Server-side HTTP failure |
| `NL-DECODE` | Invalid JSON or missing login session fields |
| `NL-RESPONSE` | Non-HTTP or empty successful response |

Other HTTP statuses retain their numeric code. Cancellation remains a
cancellation. Support codes clear on retry/navigation and are displayed only
when the app's selected environment is staging.

## Files changed

- `../test.xcodeproj/project.pbxproj`: explicit staging flags on both app configurations.
- `APIConfig.swift`: reject invalid staging environment combinations.
- `notaryledger-ios/APIService.swift`: classify login transport/response/decoding failures and emit safe request events.
- `notaryledger-ios/LoginDiagnostics.swift`: Release logging and safe diagnostic error descriptions/codes.
- `notaryledger-ios/AuthFlow.swift`: expose staging login support codes and clear them on retry/navigation.
- `notaryledger-ios/AuthFlowView.swift`: display the short support code.
- `notaryledger-iosTests/LoginConnectivityTests.swift`: environment, URL construction, transport, HTTP, and decoding regression tests.
- `scripts/verify-api-environments.py`: resolved settings and compiler regression checks.
- `scripts/staging-target-environment.patch`: portable copy of the parent project fix.
- `README.md`, `BILLING_SUBSCRIPTION.md`, and this report: environment and verification documentation.

## Verification

- Environment regression script passed for resolved Debug and Release flags,
  unoptimized/optimized APIConfig compilation, unchanged explicit production
  URL, and compiler rejection of invalid staging flag combinations.
- Debug: 67 login/API tests passed, including the four new connectivity tests.
- Release: 65 login/API tests passed with `ENABLE_TESTABILITY=YES`. The existing
  `BillingViewModelTests.swift` references Debug-only `SubscriptionStore.preview`
  and prevents an unfiltered Release test bundle from compiling. It was excluded
  from this focused Release run using `EXCLUDED_SOURCE_FILE_NAMES`; no billing
  implementation or test source was changed. The app Release build does not
  require either test override.
- A signed, optimized arm64 Release build succeeded with `STAGING STAGING_APP`
  and bundle ID `org.notaryledger.app.staging`.
- Installed and launched that Release app on the paired physical iPhone 15 Pro.
  The user confirmed **Login succeeds**.
- From the Mac, an empty JSON POST to the staging login route returned HTTP 400
  with normal certificate verification. No account credentials were sent by
  that probe. The optional maintenance endpoint returned 404, which the existing
  app intentionally treats as maintenance disabled.

Commands from the containing workspace directory:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
python3 test/scripts/verify-api-environments.py
xcodebuild -project test.xcodeproj -scheme NotaryLedger -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath .derived-data-login-device build
xcodebuild -project test.xcodeproj -scheme NotaryLedger -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath .derived-data-login-tests \
  -only-testing:testTests/ValidationAndAPITests test
xcodebuild -project test.xcodeproj -scheme NotaryLedger -configuration Release \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath .derived-data-login-tests \
  -only-testing:testTests/ValidationAndAPITests ENABLE_TESTABILITY=YES \
  EXCLUDED_SOURCE_FILE_NAMES=BillingViewModelTests.swift test
```

Validation logs are in the containing workspace's `validation-artifacts/`:
`login-environment-check.log`, `login-debug-final-tests.log`,
`login-release-focused-tests.log`, `login-release-final-build.log`,
`login-device-install.log`, and `login-device-launch.log`.

## Remaining distribution step

The verified device build uses development signing with Release compilation;
it is not a newly uploaded TestFlight build. Archive the parent staging project
with a new, unused build number and upload it to TestFlight, then verify the
distributed build. No archive was uploaded or production resource changed.

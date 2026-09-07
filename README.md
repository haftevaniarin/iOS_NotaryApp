# Notary Ledger iOS

Native SwiftUI client for the Notary Ledger backend and web app.

## Requirements

- Xcode 26.1 or newer
- iOS 26.1 SDK, matching the current project deployment target
- Notary Ledger backend reachable from the simulator or device

## API Environments

`APIConfig.swift` selects the API base URL with Swift compile flags:

- Local: `http://127.0.0.1:4000`
- Staging: `https://staging.notaryledger.org` with `STAGING`
- Production: `https://notaryledger.org` with `PRODUCTION`

In Xcode, add the flag under Build Settings, Swift Compiler - Custom Flags, Other Swift Flags:

```text
-D STAGING
```

or:

```text
-D PRODUCTION
```

## Build

Open `notaryledger-ios.xcodeproj` and run the `notaryledger-ios` scheme.

From the command line:

```bash
xcodebuild -project notaryledger-ios.xcodeproj -scheme notaryledger-ios -destination 'platform=iOS Simulator,name=iPhone 17' build
```

Use a simulator name installed on your machine if `iPhone 17` is unavailable.

## Test

```bash
xcodebuild -project notaryledger-ios.xcodeproj -scheme notaryledger-ios -destination 'platform=iOS Simulator,name=iPhone 17' test
```

The unit tests cover:

- backend model normalization
- password validation
- cancelled-order exclusion from unpaid, invoice, and dashboard totals
- API request and JSON payload construction

## Backend Contracts

Implemented primary endpoints:

- `POST /api/auth/login`
- `POST /api/auth/signup`
- `POST /api/auth/forgot-password`
- `POST /api/auth/reset-password`
- `POST /api/auth/verify-email`
- `POST /api/auth/refresh`
- `GET /api/orders`
- `POST /api/orders`
- `PUT /api/orders/:id`
- `DELETE /api/orders/:id`
- `GET /api/expenses`
- `POST /api/expenses`
- `PUT /api/expenses/:id`
- `DELETE /api/expenses/:id`
- `GET /api/reports/tax-summary?taxYear=YYYY`
- `POST /api/invoices`
- `PUT /api/profile`
- `PUT /api/profile/password`
- `POST /api/account/export`
- `DELETE /api/account`
- `POST /api/support/contact`
- `GET /api/config/maintenance`

Access and refresh tokens are stored in Keychain. The app checks remote maintenance status before authenticated backend calls. If `/api/config/maintenance` is absent, the app treats maintenance mode as disabled.

# Notary Ledger iOS

Native SwiftUI client for the Notary Ledger backend and web app.

## Requirements

- Xcode 26.1 or newer
- iOS 26.1 SDK, matching the current project deployment target
- Notary Ledger backend reachable from the simulator or device

## API Environments

`APIConfig.swift` selects the API base URL with Swift compile flags:

- Local: `http://localhost:4000`
- Staging: `https://notaryledger-staging-api.onrender.com` with `STAGING`
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
- `POST /api/auth/register`
- `POST /api/auth/forgot-password`
- `POST /api/auth/reset-password`
- `POST /api/auth/verify-email`
- `POST /api/auth/refresh`
- `GET /api/auth/me`
- `PATCH /api/auth/me`
- `PATCH /api/auth/password`
- `POST /api/auth/logout`
- `GET /api/orders`
- `POST /api/orders`
- `PUT /api/orders/:id`
- `DELETE /api/orders/:id`
- `PATCH /api/orders/:id/mileage`
- `GET /api/expenses`
- `POST /api/expenses`
- `PUT /api/expenses/:id`
- `DELETE /api/expenses/:id`
- `GET /api/credentials`
- `PUT /api/credentials`
- `GET /api/reports/tax-summary?taxYear=YYYY`
- `GET /api/stripe/billing-status`
- `POST /api/stripe/checkout-session`
- `POST /api/stripe/customer-portal-session`
- `POST /api/stripe/sync-checkout-session`
- `POST /api/account/data-export`
- `POST /api/account/deletion-request`
- `POST /api/account/deletion-cancel`
- `POST /api/support/contact`
- `GET /api/config/maintenance`

Access and refresh tokens are stored in Keychain. The app checks remote maintenance status before authenticated backend calls. If `/api/config/maintenance` is absent, the app treats maintenance mode as disabled.

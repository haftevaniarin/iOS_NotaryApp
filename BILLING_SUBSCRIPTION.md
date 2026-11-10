# Stripe-only Billing

The iOS app subscription is managed exclusively through the existing Stripe backend. Billing has a web-aligned subscription summary and a Plans screen, both using the light parchment theme. StoreKit purchasing, restore purchases, App Store subscription links, local IAP products/configuration, and the placeholder Business tier have been removed.

## Run and configure

Open `notaryledger-ios.xcodeproj` and use the **notaryledger-ios-Stripe** scheme or the normal app scheme. No StoreKit purchase configuration is needed. The app supports iOS 17+.

The existing backend remains the authority for the Stripe customer, configured monthly/annual prices, subscription, schedules, and feature access. Only the configured Free and Pro tiers are shown. Paid prices come from authenticated backend responses. Plan names, feature copy, and the free allowance live in PlanCatalog.swift. Annual savings use the web app’s rounded percentage calculation from the actual prices. Preview numbers are isolated debug fixtures.

The current Debug build uses the existing `STAGING` compile flag. Deploy backend changes to staging, or remove that flag for a local build targeting `http://localhost:4000`.

Server-only settings live in `/Users/arin/notary-backend/.env`:

```dotenv
STRIPE_ENABLED=true
STRIPE_SECRET_KEY=<server-side Stripe test or live key for that environment>
STRIPE_WEBHOOK_SECRET=<signing secret for the matching webhook endpoint>
STRIPE_PRO_MONTHLY_PRICE_ID=<configured monthly price>
STRIPE_PRO_ANNUAL_PRICE_ID=<configured annual price>
```

Never put secret keys in Xcode, client code, or the web app's environment file. Existing sandbox keys/settings remain configured locally. For local sandbox webhook forwarding, keep the workspace helper running in another terminal:

```sh
node /Users/arin/test/subscription-billing-changes/scripts/stripe-local-listener.mjs
```

The helper uses the saved local CLI signing secret and hides secret values. A deployed webhook endpoint needs its own signing secret.

## Subscription flow

- **Billing summary:** status pill, plan, state, configured billing price/interval, and current period end. A header Refresh button and pull to refresh reload backend state. Initial loading uses skeleton rows; a failed request shows Retry. Cancellation-at-period-end displays its end date and switching restriction.
- **Plans:** actual monthly/annual prices, computed annual savings and effective monthly cost, and shared plan copy. The annual interval is selected initially. Free stays hidden for subscribed users. Existing subscribers get a disabled **Subscribed** button; new subscribers can start Checkout for the selected interval. A scheduled cancellation disables the interval toggle.
- **Hosted Stripe:** Manage subscription and Subscribe request account-authorized URLs and present them in `SFSafariViewController`. Closing the sheet, returning through the app link, or becoming active refreshes the backend state. Management and cancellation remain in Stripe’s Customer Portal. No card information is displayed or collected in SwiftUI.
- **Account synchronization:** Checkout return URLs and session IDs never grant Pro access. Verified Stripe webhooks remain authoritative. Duplicate subscriptions and unfinished checkout reuse follow the existing backend protections. Existing billing return-link ownership checks are preserved.

`BillingViewModel` is observable and coordinates selection, loading/error presentation, and Safari sessions through the shared account-bound `SubscriptionStore`. The async `BillingService` protocol has live and mock implementations; its subscription, Checkout, Portal, and synchronization calls reuse the existing API service. Signing-invoice delivery tracking and its usage/history service methods remain available independently of the new subscription screen.

The native billing screens do not show or collect cards, payment methods, or billing addresses. They request `GET /api/stripe/subscription-account?view=subscription`, which excludes card/billing-detail data. Stripe's hosted pages handle any payment information. Deploy the new response projection with the native app.

The public web `mobile-billing-return.html` handoff, fallback URL scheme, associated-domain files, and configured return URL still need to be deployed/configured for the intended environment. Native return-link parsing and account-safe refresh are preserved.

## U.S. App Store distribution

The confirmed distribution is App Store/TestFlight, U.S. only. External Stripe actions are enabled only after Apple's Storefront API reports `USA`; unknown or other storefronts can view billing but cannot start external billing actions. StoreKit is used only to read the storefront, never to buy, restore, or manage subscriptions.

Recheck [App Review Guidelines 3.1.1(a)](https://developer.apple.com/app-store/review/guidelines/) before release. The current guidelines permit external purchase links in the United States storefront. Portal capabilities remain controlled by the shared [Stripe Customer Portal configuration](https://docs.stripe.com/customer-management/configure-portal), including cancellation at period end.

## Invoice usage tracking

The previously added server tracking is retained. `InvoiceDelivery` records confirmed Mail/Message sends, explicit **Mark Invoice as Sent** actions, and successful server-sent Stripe signing invoices. Saving, copying, printing, AirDrop, canceled shares, or simply generating a PDF do not increment the count. Account and delivery ID deduplication makes retries safe. One PDF containing several signing orders counts as one invoice.

- `GET /api/billing/usage?start=<ISO8601>&end=<ISO8601>` returns real account-scoped counts and existing limits.
- `POST /api/billing/invoices/sent` records a confirmed send after verifying signing-order ownership.
- `20261109000000_track_invoice_deliveries` is additive and does not invent historical send times. The local development database has other pending migrations, so the migration remains unapplied there; review those before deploying. It has been tested in an isolated database.

Generate the Prisma client and apply reviewed migrations alongside backend deployment:

```sh
cd /Users/arin/notary-backend
npm run prisma:generate
npx prisma migrate deploy
```

## Validation

Tests cover configured prices and savings, selected Checkout interval, Safari presentation state and return refresh, backend-confirmed access, cancellation restrictions, existing-subscriber duplicate prevention, retry after failure, account changes, storefront restrictions, return links, and the existing Stripe API contracts. UI checks cover the Billing → Plans → Billing route and interval selection. Layout captures cover both intervals at 375×844, 390×844 and 430×844, active/canceling/Free/loading/error states, and larger text. No real subscriptions are created by these mock-based regression tests.

The earlier real Stripe sandbox run verified Checkout creation/reuse, both interval-change directions, cancellation/reversal, payment failure/recovery, 3D Secure, and 31 accepted signed webhook deliveries. Those backend mechanisms are reused; the current provider-switch regression runs are not represented as another real sandbox run.

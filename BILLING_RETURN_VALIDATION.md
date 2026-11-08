# Stripe returns to iOS

The native app sends `clientType: "ios"` when creating Checkout and Customer Portal sessions. The backend chooses fixed return URLs; the client cannot supply a redirect destination. Web clients retain their existing `/billing` return URLs.

For iOS, Checkout success/cancel and the portal's Return link point to `/mobile-billing-return.html` on `APP_BASE_URL`. The app registers this path as a universal link on `notaryledger.org` and `www.notaryledger.org`. The web page also offers a fixed `notaryledger://billing/return` fallback for browsers that do not automatically open universal links. The return page works without a web login and forwards only the supported flow, outcome, and a valid Checkout Session ID.

Checkout success returns automatically. Stripe's general Customer Portal uses its Return to Notary Ledger link when the customer finishes; `return_url` does not automatically finish every action in the general portal. Automatic redirection after a specific portal action requires a dedicated Stripe portal flow. The general portal remains available for payment methods, invoices, billing details, and cancellation.

The app opens Billing after a return, including when it must first restore a session or ask the user to sign in. It synchronizes its existing account-owned pending Checkout Session and refreshes server billing status. A return URL never grants Pro access. Cancellation clears only the current account's pending Checkout Session. Refresh requests arriving during another billing action are queued.

## Files to release together

- iOS: native session marker, billing return parser/navigation/refresh, `NotaryLedger-Info.plist`, and `NotaryLedger.entitlements`.
- Backend: `src/routes/stripe.routes.js`, `src/services/stripe.service.js`, and `src/services/billing-return.service.js`.
- Web: `public/mobile-billing-return.html`, `public/mobile-billing-return.js`, `public/.well-known/apple-app-site-association`, and `public/_headers`.

Rebuild/reinstall iOS and deploy the backend and web changes. The association file uses the project's signing team `P9PYC7J262` and bundle ID `org.notaryledger.ios`; confirm the release app identifier prefix matches that value. The app ID/provisioning profile must enable Associated Domains. The association file must be served over HTTPS with `application/json` and no redirects. The supplied `_headers` config handles this on hosts supporting that convention; configure the equivalent response headers on other hosts. Staging hosts can use the custom-scheme fallback; native universal links are configured for the production hosts.

No Stripe account settings, live subscriptions, or deployments are changed by the local validation. Backend route tests requiring a database should run against an isolated test database. Before release, exercise Checkout success, Checkout cancellation, and the portal Return link in Stripe test mode on a device with the rebuilt app installed. Check both running-app and cold-start returns, plus a signed-out return. If the browser falls back to the web page, verify Return to Notary Ledger opens the app.

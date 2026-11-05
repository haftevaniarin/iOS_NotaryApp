# Authentication flow alignment

Updated November 3, 2026. Reference: the checked-out web app at commit
`642cfc6`, principally `src/App.jsx` authentication handlers, verification page,
password validation, and `src/lib/api.js` error normalization.

The native screens now share `AuthFlowModel` and `AuthFlowView`, so navigation
keeps the correct messages and form values together.

| Action / outcome | iOS behavior aligned with web |
| --- | --- |
| Login validation | “Please enter your email.” / “Please enter your password.” |
| Bad login, unverified email, rate limit | Stay on sign-in and display the safe server message; a login 401 no longer becomes a generic session-expired error. |
| Successful login | Dashboard, or the supported protected destination requested before authentication. Clear the form. |
| Signup validation | Require both names, enforce the 100-character name limit, validate email, use the web's complete password-requirements message, and check confirmation. Spaces do not count as password symbols. |
| Duplicate signup | Stay on signup with “An account with this email already exists. Please sign in or use a different email address.” Preserve entered values. |
| Verification-required signup | Return to sign-in with the server message (or the web default), preserve the trimmed email, and clear names/passwords. Verification flags take precedence over any supplied token. |
| Immediately authenticated signup | Enter the app at Dashboard or the intended destination. |
| Forgot-password success | Stay on recovery with “If an account exists for that email, a password reset link has been sent.” Clear the form. |
| Missing reset token | Show the web's missing-token message and disable submission. |
| Reset failure | Stay on reset with the error and entered values. |
| Reset success | Return to sign-in with “Your password has been reset. Sign in with your new password.” Clear the token, credentials, and local session. |
| Email verification | Distinct loading, success, invalid/expired-link, and network/server-error screens with the web's titles, messages, and sign-in/create-account actions. Verification does not automatically log in. |
| Repeated verification link | Share an in-flight request; reuse completed success/invalid results. Network/server errors remain retryable. |
| Expired protected session | Return to sign-in with “Your session has expired. Please sign in again.” Remember the destination for the next login. |
| Session restoration / logout | Show restoration progress before entering the app; preserve a protected incoming destination. Logout clears auth drafts and returns to a clean sign-in. |

Auth tabs clear stale error/success banners. Passwords have show/hide controls;
validation and completion bring the message into view. Terms and Privacy remain
accessible before authentication. The related change-password screen also uses
the web's validation order and confirmation wording.

Incoming URL handling recognizes exact auth paths and reset query/fragment
tokens. Destinations are selected from known native sections; arbitrary redirect
URLs are ignored. Native page equivalents include web `orders` → Signings and
`reports`/`tax-summary` → Tax Summary. Non-admin users cannot land on admin audit.

Validation passed on the iPhone 17 Pro simulator (iOS 26.1):

- Full regression run: 70 Swift Testing tests, seven XCTest PDF/render checks,
  and all six interactive auth UI scenarios.
- Final auth/verification rerun: 38 API/auth tests, including the additional
  concurrent verification-link case, plus the verification UI scenario.
- Final top-level Release simulator build and whitespace checks.

The UI cases exercise duplicate signup, verification-required signup, invalid
login followed by successful login to Billing, recovery, reset confirmation,
and successful/expired verification links. They assert complete password entry
and visibility toggling. Fixture launches suppress the simulator's automatic
strong-password prompt so scripted input can proceed; normal Debug and Release
launches retain native Password AutoFill roles.

Screen renders at 375 and 440 pt are in
[`../validation-artifacts/authentication`](../validation-artifacts/authentication).
Passing result bundles under `../.derived-data-module-fixed/Logs/Test/`:

- `Test-notaryledger-ios-2026.11.03_20-37-46--0800.xcresult` (full run).
- `Test-notaryledger-ios-2026.11.03_20-52-01--0800.xcresult` (final focused run).

Network and UI scenarios used isolated fixtures; no live accounts were created
or changed. Real email delivery, OS universal-link handoff, and password-manager
AutoFill on physical hardware were not exercised. Native sessions continue to
use Keychain refresh tokens, and native network-error wording can differ from a
browser's network errors.

# Accounting Reports

Accounting includes a separate Reports destination alongside Tax Summary. Reports matches the web report choices: Overview, Income, Profit & Loss, Outstanding Payments, Mileage, Expenses, and Clients.

The source contracts inspected were `billing-redirect-changes/web-validation/src/App.jsx` (`ReportsPage` and its filters), `src/lib/reports.js`, and the existing backend `reports.routes.js` / `reports.service.js` in `subscription-billing-changes/validation-backend`.

The native page reuses authenticated GET endpoints under `/api/reports`: `overview`, `income`, `profit-loss`, `outstanding-payments`, `mileage`, `expenses`, and `clients`. No backend or database migration is required. Deployments must expose those existing report routes; a missing route displays an unavailable message and retry action.

Period presets match the web's local Gregorian calendar-day ranges, including full current/previous months, year to date, last year, and custom dates. Requests send explicit `startDate` and `endDate`, `period`, and optional `clientId`, `paymentStatus`, and `orderStatus`. Customer/client IDs are now retained when decoding orders; legacy names are never sent as client IDs. The client selector is disabled when no actual IDs are available.

All totals, monthly series, aging buckets, expense allocations, mileage records, and client rankings come from the backend. The app does not independently recalculate revenue, partial payments, aging, tax deductions, or mileage rates. Decimal amounts are preserved, and null/absent metrics are omitted. Charts use floating-point coordinates only for rendering; displayed financial values retain Decimal precision.

Reports supports loading, empty, unavailable, and retry states, pull to refresh, stale-response rejection, Dynamic Type, native accessible controls, and the existing light theme. Outstanding records link to their matching signing details when that order is loaded. Switching bottom tabs resets Accounting to its main list. `/reports` links now open Reports; `/tax-summary` remains Tax Summary.

The inspected backend returns no CSV/PDF export links for these business reports. The existing Tax Summary PDF export remains available separately.

Tests cover all seven authenticated endpoints and query fields, direct/wrapped responses, exact amounts, missing values, customer IDs, date presets across year/leap-day/DST boundaries, invalid ranges, stale responses, and error states. Simulator checks exercise all seven report choices, Accounting navigation reset, protected Reports links, and retry for an unavailable endpoint. They use isolated fixtures and do not access live account data.

# Notary Ledger iOS Mobile Web Parity Notes

This implementation treats the current mobile web brief as the source of truth for the SwiftUI app.

## Screen Mapping

- Login: `LoginView`, using parchment auth shell, NL seal, validation banner, and account links.
- Sign Up: `SignUpView`, using the same auth shell, profile fields, password confirmation, and validation banner.
- Forgot Password: `ForgotPasswordView`, using the auth shell, email field, reset CTA, success/error banners.
- Reset Password: `ResetPasswordView`, using the auth shell, password fields, reset CTA, success/error banners.
- Email Verification: `VerificationView`, using an iOS sheet with NL seal and verification state.
- Dashboard: `DashboardView`, using top-bar title, date subtitle, credential warning banner, upcoming signings above stats, stat cards, travel totals, and recent activity cards.
- Signings: `SigningsView`, using search, status filter, mobile signing cards, New Signing, Import, Edit, Delete, Mileage & Travel, and Generate Invoice PDF sheets.
- Rescission Calculator: `RescissionCalculatorView`, using compact mobile cards for inputs and calculated deadline.
- Invoices: `InvoicesView`, using customer selection, customer/signer details, line item cards, balance, custom invoice fields, and PDF result state.
- Expenses: `ExpensesView`, using search, expense cards, Log Expense, Edit, Delete, receipt extraction, category, amount, date, deductible, and loading/empty/error states.
- Customers: `CustomersView`, using cards derived from signing history with latest signing, signing count, unpaid work, revenue, and invoice action affordance.
- Tax Summary: `TaxSummaryView`, using tax year selector, income, expenses, travel/mileage, estimated tax cards, and PDF export.
- Billing: `BillingView`, using current plan/status, Free/Pro/past due/canceled/inactive states, upgrade sheet, and account portal sheet.
- Profile: `ProfileView`, using account fields, credential fields, password section, data/privacy controls, account deletion request/cancel, support entry, and sign out.
- Terms & Conditions: `LegalDocumentView(kind: .terms)`.
- Privacy Policy: `LegalDocumentView(kind: .privacy)`.
- Admin Audit Logs: `AdminAuditLogsView`, hidden from the menu unless `AuthUser.canAccessAdminAudit` is true.

## Component Library Equivalents

- Colors and typography: `NLColor`, `NLFonts`.
- NL seal and wordmark: `NLSeal`, `BrandLockup`.
- Sticky navy top bar: `LedgerTopBar`.
- Slide-out navy side menu: `LedgerSideMenu`.
- Cards and panels: `NLCard`, `PanelModifier`.
- Buttons: `PrimaryButtonStyle`, `SecondaryButtonStyle`, `ActionPill`.
- Banners: `BannerView`, `ErrorBanner`.
- Fields: `NLTextField`, `NLSecureField`, `FieldLabel`.
- Badges: `StatusBadge`.
- Empty states: `EmptyStateView`.
- Tables-as-cards: `SigningOrderCard`, `ExpenseCard`, `CustomerSummaryCard`, `TaxSummaryCard`.
- Sheets: signing form, import signings, delete confirmation, mileage/travel, invoice PDF, expense form, receipt extraction, billing upgrade/portal, support contact, and account deletion request.

## Prototype Flow Coverage

- Authentication: login, sign up, forgot password, reset password, email verification.
- Navigation: hamburger opens the navy drawer; drawer changes the active screen and preserves legal/admin links.
- Dashboard navigation: dashboard actions open New Signing.
- Signings: new/edit/delete/import/mileage/invoice actions are reachable from the card list.
- Expenses: log/edit/delete/receipt extraction actions are reachable from the card list.
- Invoices: customer-generated invoice PDF flow and custom invoice fields are represented.
- Billing: upgrade and manage billing sheets cover checkout/account-portal states.
- Profile: change password, support, data export, deletion request, cancellation, and logout are represented.

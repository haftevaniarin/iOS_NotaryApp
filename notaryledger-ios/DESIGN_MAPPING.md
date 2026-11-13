# Notary Ledger iOS Mobile Web Parity Notes

This implementation treats the current mobile web brief as the source of truth for the SwiftUI app.

## Screen Mapping

- Login: `LoginView`, using parchment auth shell, NL seal, validation banner, and account links.
- Sign Up: `SignUpView`, using the same auth shell, profile fields, password confirmation, and validation banner.
- Forgot Password: `ForgotPasswordView`, using the auth shell, email field, reset CTA, success/error banners.
- Reset Password: `ResetPasswordView`, using the auth shell, password fields, reset CTA, success/error banners.
- Email Verification: `VerificationView`, using an iOS sheet with NL seal and verification state.
- Dashboard: `Features/Dashboard/DashboardView`, using the dated greeting, next-signing hero, three quick actions, monthly stats, attention rows, and upcoming signings. See `DASHBOARD_IMPLEMENTATION.md` for repository and preview details.
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

- Colors and typography: `NLColor`, `NLFonts`; the Dashboard semantic colors, font weights, spacing, and radii live in `DesignSystem/Theme.swift`.
- NL seal and wordmark: `NLSeal`, `BrandLockup`.
- Main navigation: native four-tab `LedgerAppShell` (Home, Signings, Money, Profile), with a profile-photo/initials icon for Profile.
- Legacy top-bar/drawer components remain available for older snapshots; the Dashboard uses the real system safe area and native tab bar.
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
- Navigation: native tabs select Home, Signings, Money, and Profile; Journal is hidden from the Dashboard and Profile menu. Money and Profile retain the existing invoice, expense, report, account, legal, and permitted admin destinations; protected links still select the appropriate tab and destination.
- Dashboard navigation: quick actions, notifications, and Open file use placeholder sheets pending destination work. Navigate opens Apple Maps for known addresses. See all selects the existing Signings tab; its New Signing action retains the live order form.
- Signings: new/edit/delete/import/mileage/invoice actions are reachable from the card list.
- Expenses: log/edit/delete/receipt extraction actions are reachable from the card list.
- Invoices: customer-generated invoice PDF flow and custom invoice fields are represented.
- Billing: upgrade and manage billing sheets cover checkout/account-portal states.
- Profile: change password, support, data export, deletion request, cancellation, and logout are represented.

# Dashboard

The SwiftUI screen supports iOS 17+. `Features/Dashboard` contains the observable view model, repository protocol, in-memory/mock implementations, preview data, and the five requested components. `Models/DashboardModels.swift` defines the new Decimal-based models. `DesignSystem/Theme.swift` contains semantic Dashboard colors and Dynamic Type fonts while preserving the existing billing tokens/styles. The bundled Fraunces and IBM Plex Sans static files already provide weights 400/500/600 and remain registered in `NotaryLedger-Info.plist`.

`Features/Navigation/LedgerAppShell.swift` supplies a native four-tab `TabView` (Home, Signings, Money, Profile). Home has no custom status bar or legacy navy header. Existing signing creation stays available in Signings; invoice/expense/report pages are under Money, and account/legal/admin pages are under Profile. Existing protected URLs route to the matching tab and navigation path. Authentication and backend billing rules were not changed.

## Data boundary

`DashboardRepository.load()` is the async boundary for a future Dashboard API. `InMemoryDashboardRepository` can load an immutable snapshot or a current in-memory source; `MockDashboardRepository` supports both successful and failing responses. Ordinary failures surface a retry state, canceled refreshes retain prior state, and superseded responses cannot replace newer data. Pull to refresh reloads the repository.

The production host reads the ledger that AppState has already loaded. It adds no Dashboard networking, credential requests, push registration, or location permissions. Synthetic values are isolated in `PreviewData` and explicit debug UI fixtures; production account totals never use the sample snapshot. The preview collection covers loaded, empty, loading, error, and AX3.

Currency values in the new models, calculations, and presentation use Decimal and currency FormatStyle. The compatibility adapter converts the existing legacy Double fields through their decimal string representation before calculating; the old backend/data models are unchanged. Date/time labels use the user's locale. Offset-bearing order timestamps use the existing scheduling helper and local zone.

## Assumptions

- The public reference wrapper could be retrieved, but its embedded design could not be rendered (the frame URL returned 404). The written 390×844 specification is the visual source; exact pixel comparison with the artifact remains unavailable.
- The live adapter keeps the existing dashboard's signing-date grouping. Net income is paid signing fees less recorded business-use expenses and parking/tolls for that month. It is not a tax estimate. Prior-month comparison is omitted when the previous net is zero or negative.
- No appointment end times, missing addresses, live GPS distances, or credential reminders are invented. Known trip addresses/one-way miles are reused; Navigate is disabled for missing addresses. Credential/bond attention items can be supplied by the future repository; the mock snapshot demonstrates the layout.
- Quick actions, Notifications, and Open file intentionally open placeholder routes. See all goes to the existing Signings page. Journal is hidden from the Dashboard actions, Profile menu, and bottom navigation.
- Greeting text follows the local time of day; the loaded preview uses a fixed morning. The normal 390-point stats layout is 2×2. Very narrow screens and accessibility sizes stack stats; accessibility quick actions become 2×2, and upcoming date blocks scale with Dynamic Type.

## Validation

The iPhone 15 simulator checks cover model selection, bounded/sorted upcoming data, no duplicate hero, error/retry, canceled and superseded loads, Decimal arithmetic, missing address behavior, Maps URL encoding, and tab ownership. Layout captures cover 320/390/430-point widths in loaded, empty, skeleton, error, and AX3 states, plus a tall AX3 component capture. UI checks exercise all four tabs, placeholder actions, shared subscription access, billing navigation, legal return links, and refresh.

Xcode's AppIntents metadata phase may print its existing skip notice because this app does not link that framework; no AppIntents dependency or warning-suppression setting was added just to hide it.

## Profile tab icon

The Profile tab uses the signed-in user’s profile photo as a circular native tab image. It displays first/last initials while loading, for a missing URL, or after an unavailable/unreadable photo. When name initials are unavailable, the email’s first letter is used, followed by the app initials if no account name/email is available. User/photo changes refresh the icon, and late photo responses from another account are ignored. Photos are downsampled before rendering and no photo URLs or personal details are logged. The profile-photo/initials icon is retained; the tab and menu heading are named Profile.

# Credentials editor

Completed November 3, 2026.

Profile now shows saved credential summaries with expired/expiring-soon badges
and a collapsible editor for commission, E&O insurance, background check, and
an additional credential. Saves validate dates and coverage, preserve edits on
failure, prevent duplicate submissions, and update summaries from the server
response. Clearing an entire credential sends JSON nulls. Dashboard reminders
use the same calendar-day expiration rules.

Rendering exposed an iOS 26.1 crash when SwiftUI released an actor-isolated
model outside a Swift task. Explicit nonisolated deinitializers in the editor
model and shared app state avoid it; neither has actor-bound cleanup.
See [Swift issue 88036](https://github.com/swiftlang/swift/issues/88036).

Validation passed on the iPhone 17 Pro simulator running iOS 26.1:

- 55 Swift Testing tests, including eight editor tests and an authenticated
  GET/PUT round trip using fixture responses.
- Both XCTest rendering checks: 94 existing screen renders plus eight focused
  credentials renders at 375, 402, and 440 pt, including empty and large-text states.
- Release simulator builds and `git diff --check`.

Review the [summary](../validation-artifacts/credentials/final/ios-375-Credentials%20Summary.png),
[expanded editor](../validation-artifacts/credentials/final/ios-375-Credentials%20Expanded.png),
and [large text](../validation-artifacts/credentials/final/ios-375-Credentials%20Large%20Text.png).
The final test bundle is
`../.derived-data-module-fixed/Logs/Test/Test-notaryledger-ios-2026.11.03_15-01-11--0800.xcresult`.

Network checks used fixtures; no live account credentials were changed.

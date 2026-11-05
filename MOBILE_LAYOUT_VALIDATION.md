# Mobile web typography and layout alignment

Updated November 2, 2026. Reference: the checked-out web app's `src/App.jsx`
mobile rules and `src/business-card/business-card.css`.

| Element | Default mobile size |
| --- | --- |
| Page title | Fraunces, 23 pt, semibold |
| Section / modal title | Fraunces, 19 pt, semibold |
| Card heading | Fraunces, 15–15.5 pt, semibold |
| Body and action text | IBM Plex Sans, 13.5 pt |
| Input, select, and date field | IBM Plex Sans, 14 pt |
| Field label | IBM Plex Sans, 12 pt, semibold |
| Status badge | IBM Plex Sans, 11.5 pt, semibold |
| Dashboard metric | IBM Plex Mono, 20 pt |
| Business-card title | Fraunces, 28 pt, bold |
| Business-card labels / inputs | IBM Plex Sans, 14 / 15 pt |

Phone layouts use 14 pt horizontal and 16 pt vertical screen insets, a 58 pt
header, a 264 pt navigation drawer, and a single dashboard metric column.
The shared layout also implements the web's 640 and 980 px breakpoints for
content insets, page headings, and metric columns. Card padding is 20 pt;
signing cards use the web mobile list's 14 pt inset. Form fields, menu fields,
and date fields share the web input styling. Business-card inputs have a
46 pt minimum height. Long text can wrap, action rows stack when needed,
and custom fonts continue to scale with Dynamic Type.

Font files and redistribution notices are bundled under `notaryledger-ios/Fonts`.
NLDisplay and NLBody are static instances of Fraunces and IBM Plex Sans;
their provenance is recorded in that directory's README.

Validation artifacts are in `../validation-artifacts/mobile-layout`:

- `web-measurements.json`: browser measurements at 375, 402, and 440 CSS px.
- `web-*.png`: local web reference screenshots using its built-in mock account.
- `ios-current/`: final iOS screenshots exported from `MobileLayoutTests`, with readable names
  such as `ios-375-Profile.png` and `ios-375-New Signing.png`.
- The renderer covers 31 screens at each of the three widths, plus a large-text
  Profile render: 94 images. Fixture services isolate the rendered screens from
  staging and never perform account or billing changes.

Final checks passed: 44 Swift Testing unit tests, the XCTest rendering test,
the login/recovery UI smoke test, and the Release simulator build. `git diff
--check` passed. Representative renders:
[Profile](../validation-artifacts/mobile-layout/ios-current/ios-375-Profile.png),
[signing form](../validation-artifacts/mobile-layout/ios-current/ios-375-New%20Signing.png),
and [large text](../validation-artifacts/mobile-layout/ios-current/ios-375-Profile%20Large%20Text.png).

The web's business-card mock route could not load its editor data, so its
field sizing was checked against its source stylesheet. Native safe areas,
calendar selection panels, popup menus, switches, and system navigation chrome
remain platform-specific. The renders provide visual review artifacts;
they are not automated pixel-difference assertions against the web screenshots.

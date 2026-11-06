# Tax PDF template alignment

Updated November 5, 2026. Reference: web checkout `642cfc6`,
`src/App.jsx` → `handleGenerateTaxPdf`, its shared PDF drawing helpers, and the
tax-summary report endpoint's response fields.

The iOS export now follows the web's Letter-size template: 44 pt margins,
Helvetica/Times fonts, navy/brass/parchment palette, seal, generated-date and
tax-year panel, taxpayer card, lettered A–D sections, metric cards, detail tables,
1099 review badges, paid-date warning, mileage card, net-income panel, notices,
estimated payments, CPA note, and numbered footers.

Export fetches a fresh authenticated report with the selected year and the
web's cache-busting query parameter. It preserves full client/category/payment
detail, shows the web's totals-only or empty sections when appropriate, disables
duplicate export taps, and saves a shareable PDF with the web-style filename.
Changing years during a request prevents exporting the previous selection.

Financial amounts remain the backend's report values. The renderer does not
recalculate tax. Decimal-string amounts are supported, including the backend's
client `totalIncomeReceived` field. Invoice and tax PDFs share drawing primitives;
invoice regression checks passed after extracting those primitives.

Validation passed:

- 72 Swift Testing tests and 12 XCTest checks (84 total), including tax PDF,
  invoice PDF, authenticated fresh-fetch, and screen-rendering regressions.
- Complete, totals-only, and empty reports compared against PDFs produced by
  the actual web drawing code with the same fixture figures. Page counts match:
  three, three, and two respectively. Every page was rendered at 1224 × 1584 px.
- A 100-client report retains every row over seven pages with repeated table
  headings and footers. Decimal parsing and malformed-data checks passed.
- Top-level Release simulator build and whitespace checks passed.

| Fixture | Web reference | iOS result |
| --- | --- | --- |
| Complete detail | [PDF](../validation-artifacts/tax-documents/web-full.pdf) | [PDF](../validation-artifacts/tax-documents/ios-tax-full.pdf) |
| Totals only | [PDF](../validation-artifacts/tax-documents/web-summary.pdf) | [PDF](../validation-artifacts/tax-documents/ios-tax-summary.pdf) |
| Empty report | [PDF](../validation-artifacts/tax-documents/web-empty.pdf) | [PDF](../validation-artifacts/tax-documents/ios-tax-empty.pdf) |
| Large report | — | [PDF](../validation-artifacts/tax-documents/ios-tax-multipage.pdf) |

PNG pages, fixture JSON, reference-generation script, and comparison measurements
are alongside these PDFs. Native text wrapping/font rasterization can differ
slightly; the PDFs are not byte-identical. Long names and rows can expand or
continue across pages instead of clipping.

Passing full-run bundle:
`../.derived-data-module-fixed/Logs/Test/Test-notaryledger-ios-2026.11.05_09-19-58--0800.xcresult`.
Validation used fixtures and did not modify live accounts or tax records.

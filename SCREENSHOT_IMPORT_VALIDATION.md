# Screenshot order import

The Signings screen offers **New Signing** and **Bulk Import Signings**. Bulk import creates multiple orders from CSV, TSV, or UTF-8 TXT spreadsheet exports. Screenshot extraction is available inside New Signing.

The **New Signing** form includes **Extract Order from Screenshot**. This returns extracted details to the same form, filling blank fields and appending labeled details to existing notes. Manually entered values and an explicitly selected date are kept. Cancelling or failing extraction leaves the form unchanged. Successful extraction displays the screenshot and requires the same review, field confirmations, and duplicate check before the form can save. No separate order is created by the picker.

Open Signings → New Signing → Extract Order from Screenshot → Choose Screenshot. The system photo picker grants access only to the selected image. Alternatively, use Choose Image from Files. Both image sources use the same on-device pipeline. Bulk import accepts spreadsheet exports only and presents a Review Bulk Import screen before importing rows.

`ScreenshotTextRecognition` uses Apple's Vision framework on a background task. It handles image orientation, groups observations into reading rows, and passes recognized text and confidence to the deterministic extractor. It does not call an extraction API, store screenshots, or log recognized text. Order API error response bodies are excluded from debug logs because they may echo personal information.

The extractor accepts labels in varying orders, separate label/value lines, inline columns, multiple signers, and multiline instructions and addresses. It supports aliases rather than a fixed screenshot template. Unsupported layouts remain available for manual review in the source image. Missing values and unavailable placeholders remain blank. Conflicting values and ambiguous or invalid dates, times, fees, and contact details remain blank with the original evidence displayed. Low-confidence recognized values carry a review warning.

## Existing field mapping

| Screenshot detail | Order field |
| --- | --- |
| Signing or title company | Customer name |
| Signer names | Signer name |
| Appointment type | Signing type |
| Signing date | Date, without a default date |
| Signing time | Time, normalized only when unambiguous |
| Notary fee | Fee |
| Order reference, contacts, location, document type, special instructions | Labeled Notes |

An order reference does not become an invoice number. Payer and invoice fields stay blank until entered. The existing required fields and 255 UTF-16 character notes limit still apply. Long notes block saving until the user edits them; no extracted detail is silently truncated.

The user must confirm the date and USD fee, confirm any recognized time or deliberately leave it blank, and agree to send the reviewed form to their account. Editing a form field resets the overall review consent. Editing date, time, or fee also resets that field's confirmation. Times from other zones must be converted to the device's local zone before confirmation, matching the existing order encoder.

Before creating an order, the form fetches the current orders and checks normalized references, or signer plus local signing date plus location. References use labeled Notes and existing invoice numbers; locations use labeled Notes and existing trip destination addresses. Existing orders without any stored reference or location cannot match those respective checks. Matches require an additional duplicate confirmation. A failed duplicate lookup blocks saving and allows retry. These are client-side checks; simultaneous saves from multiple devices can still race.

## Validation

Run `ScreenshotOrderImportTests`, `OrderFormValidationTests`, and `OrderParsingTests` using the `notaryledger-ios` scheme on an iOS simulator. Coverage includes field mapping, omitted values, low confidence, alternate layouts, multiple signers, conflicting values, ambiguous date/time/fee parsing, confirmation requirements, duplicate detection, local calendar handling, malformed contacts, notes limits, and actual on-device Vision recognition of a generated screenshot.

Manual checks: select and cancel a photo; try a blurry image and an unrelated screenshot; compare the screenshot and editable fields; correct ambiguous values; verify confirmation resets after edits; verify duplicate warnings and failed save retry; check VoiceOver and large Dynamic Type on the review screen. The screenshot is never attached to the saved order.

# Legal page parity

The reference is `LEGAL_PAGES` and `LegalPage` in the web app's `src/App.jsx`, revision `642cfc6`.

- Both documents use the complete web wording, including all nine sections per document (18 Terms paragraphs and 22 Privacy paragraphs), introductions, subtitles, the July 19, 2026 update date, template notice, and support address.
- The iOS layout uses the web's introduction card, a single card containing numbered sections with serif headings, and a contact card with an expandable support form.
- The form uses the web's five topic labels, validation messages, success message, retained contact details, cleared message fields after success, and `terms`/`privacy` source identifiers. Requests work before sign-in and can optionally include the signed-in account's access token.
- Two display labels need API-compatible values: Product support sends `other`; Bug report sends `technical`. These match the backend's support schema while keeping the web's choices visible.
- “Sign in” returns to the login screen, including when a policy was opened from signup. “Back to dashboard” returns to the dashboard when signed in.

`LegalParityTests` fingerprints every document title, subtitle, introduction, section heading, and paragraph against hashes independently generated from the web source. It also checks support validation, submission, retry behavior, prefill, anonymous and authenticated requests, and server error handling. The UI tests exercise both documents from signup and the sidebar. `MobileLayoutTests` captures the documents at 375, 402, and 440 point widths.

Support submissions in automated checks use isolated local fixtures; they do not send real support messages. Policy text is bundled, so subsequent web policy updates require an iOS content update and release.

Validation passed: 82 Swift Testing cases, 12 XCTest cases (including phone-width rendering), two legal navigation UI tests, and the Release simulator build. Reviewed screenshots are in `../validation-artifacts/legal-pages/`.

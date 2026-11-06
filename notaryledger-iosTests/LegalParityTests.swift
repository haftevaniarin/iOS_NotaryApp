import CryptoKit
import Foundation
import Testing
@testable import notaryledger_ios

@MainActor
struct LegalParityTests {
    @Test func entireDocumentsMatchWebSourceRevision642cfc6() {
        // Fingerprints generated independently from App.jsx's LEGAL_PAGES.
        // Includes titles, subtitles, intros, section order and every paragraph.
        let fingerprints: [LegalDocumentKind: String] = [
            .terms: "b02e9fadea2aee0ac651600289e5af438004ebafa013234dc14327991d81b487",
            .privacy: "7c828f655c7025fd8a928caad62b699ff786322d422602e9224473ed673a5e8c"
        ]
        for kind in LegalDocumentKind.allCases {
            let content = kind.content
            let lines = [content.title, content.subtitle, content.intro]
                + content.sections.flatMap { [$0.title] + $0.paragraphs }
            let digest = SHA256.hash(data: Data(lines.joined(separator: "\n").utf8))
                .map { String(format: "%02x", $0) }.joined()
            #expect(digest == fingerprints[kind])
            #expect(kind.subtitle.hasSuffix("Last updated July 19, 2026."))
        }
        #expect(LegalDocumentKind.supportEmail == "support@notaryledger.org")
    }

    @Test func supportValidationMatchesWebAndDoesNotSubmitInvalidDrafts() async {
        let model = LegalSupportContactModel(sourcePage: "terms", send: { _ in
            Issue.record("Invalid requests must not be sent")
        })
        await model.submit()
        #expect(model.fieldErrors == [
            "name": "Please enter your name.", "email": "Please enter your email.",
            "subject": "Please enter a subject.", "message": "Please enter a message."
        ])
        model.draft = SupportContactDraft(name: "Avery", email: "avery@invalid", subject: "Question", message: "short")
        await model.submit()
        #expect(model.fieldErrors == ["email": "Please enter a valid email address.", "message": "Please add a little more detail."])
        model.update(\.email, field: "email", value: "avery@example.test")
        #expect(model.fieldErrors["email"] == nil)
        #expect(model.fieldErrors["message"] == "Please add a little more detail.")
    }

    @Test func supportSuccessUsesWebCopyAndResetsMessageWhileKeepingContactDetails() async {
        for (topic, apiTopic) in [("Account access", "Account access"), ("Billing", "Billing"),
                                 ("Product support", "other"), ("Privacy request", "Privacy request"), ("Bug report", "technical")] {
            let model = LegalSupportContactModel(sourcePage: "privacy", send: { request in
                #expect(request == SupportContactRequest(name: "Avery", email: "avery@example.test", topic: apiTopic,
                                                         subject: "Question", message: "Please help with my account.", sourcePage: "privacy"))
            })
            model.draft = SupportContactDraft(name: " Avery ", email: " avery@example.test ", topic: topic,
                                              subject: " Question ", message: " Please help with my account. ")
            await model.submit()
            #expect(model.success == "Support request sent to support@notaryledger.org. We'll follow up by email.")
            #expect(!model.isSubmitting)
            #expect(model.draft.name == " Avery " && model.draft.email == " avery@example.test ")
            #expect(model.draft.subject.isEmpty && model.draft.message.isEmpty)
            #expect(model.draft.topic == "Account access")
            model.update(\.subject, field: "subject", value: "Another question")
            #expect(model.success.isEmpty)
        }
    }

    @Test func supportFailureKeepsDraftAndFieldErrorsForRetry() async {
        var attempts = 0
        let model = LegalSupportContactModel(sourcePage: "terms", send: { _ in
            attempts += 1
            if attempts == 1 {
                throw SupportContactFailure(message: "Please complete all required fields.", fieldErrors: ["subject": "Subject is too long."])
            }
        })
        model.draft = SupportContactDraft(name: "Avery", email: "avery@example.test", subject: "Question", message: "Please help with my account.")
        await model.submit()
        #expect(model.error == "Please complete all required fields.")
        #expect(model.fieldErrors["subject"] == "Subject is too long.")
        #expect(!model.isSubmitting && model.draft.message == "Please help with my account.")
        model.update(\.subject, field: "subject", value: "Shorter subject")
        #expect(model.error.isEmpty && model.fieldErrors.isEmpty)
        await model.submit()
        #expect(attempts == 2 && !model.success.isEmpty)
    }

    @Test func contactPrefillDoesNotOverwriteUserEdits() {
        let model = LegalSupportContactModel(sourcePage: "terms")
        model.prefill(AuthUser(id: "u", fullName: "Avery Notary", email: "avery@example.test"))
        #expect(model.draft.name == "Avery Notary" && model.draft.email == "avery@example.test")
        model.draft.name = "Business owner"
        model.draft.email = "owner@example.test"
        model.prefill(AuthUser(id: "u", fullName: "Updated Name", email: "updated@example.test"))
        #expect(model.draft.name == "Business owner" && model.draft.email == "owner@example.test")
    }
}

extension ValidationAndAPITests {
    @Test func legalContactSupportsAnonymousAndOptionalAuthenticatedRequests() async throws {
        let previousToken = SessionStorage.getAccessToken()
        defer {
            MockURLProtocol.requestHandler = nil
            MockURLProtocol.requests = []
            if let previousToken { SessionStorage.saveAccessToken(previousToken) } else { SessionStorage.clearTokens() }
        }
        for token: String? in [nil, "support-fixture-token"] {
            if let token { SessionStorage.saveAccessToken(token) } else { SessionStorage.clearTokens() }
            MockURLProtocol.requestHandler = { request in
                #expect(request.url?.path == "/api/support/contact")
                #expect(request.httpMethod == "POST")
                #expect(request.value(forHTTPHeaderField: "Authorization") == token.map { "Bearer " + $0 })
                let payload = try JSONDecoder().decode(SupportContactRequest.self, from: #require(request.httpBody))
                #expect(payload.sourcePage == "privacy")
                return MockURLProtocol.jsonResponse(for: request, body: #"{"success":true,"message":"Sent."}"#)
            }
            let api = APIService(baseURL: "https://support.example.test", session: MockURLProtocol.session())
            api.onAuthenticationRequired = { Issue.record("Public support must not redirect to authentication") }
            try await api.contactSupport(SupportContactRequest(name: "Avery", email: "avery@example.test", topic: "Privacy request",
                                                               subject: "Question", message: "Please help with my account.", sourcePage: "privacy"))
        }
    }

    @Test func legalContactKeepsServerErrorsIncludingFailedSuccessEnvelopes() async throws {
        defer {
            MockURLProtocol.requestHandler = nil
            MockURLProtocol.requests = []
        }
        for status in [200, 400, 429] {
            MockURLProtocol.requestHandler = { request in
                MockURLProtocol.jsonResponse(for: request, statusCode: status,
                    body: #"{"success":false,"message":"Please try again.","fieldErrors":{"email":["Email is invalid."]},"error":{"details":[{"field":"subject","message":"Subject is too long."}]}}"#)
            }
            let api = APIService(baseURL: "https://support.example.test", session: MockURLProtocol.session())
            do {
                try await api.contactSupport(SupportContactRequest(name: "Avery", email: "avery@example.test", topic: "Billing",
                                                                   subject: "Question", message: "Please help with my account.", sourcePage: "terms"))
                Issue.record("Failed support responses must not show success")
            } catch let error as SupportContactFailure {
                #expect(error.message == "Please try again.")
                #expect(error.fieldErrors == ["email": "Email is invalid.", "subject": "Subject is too long."])
            }
        }
    }
}

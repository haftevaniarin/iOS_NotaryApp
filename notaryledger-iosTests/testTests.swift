import Foundation

#if canImport(Testing)
import Testing
@testable import notaryledger_ios

struct ValidationAndAPITests {
    @Test func passwordValidationRequiresLengthAndComplexity() {
        #expect(PasswordValidation.message(for: "Short1!") == "Use at least 12 characters.")
        #expect(PasswordValidation.message(for: "            ") == "Password cannot be only whitespace.")
        #expect(PasswordValidation.message(for: "alllowercasepassword") == "Use at least 3 of lowercase, uppercase, number, and symbol.")
        #expect(PasswordValidation.message(for: "StrongPass12!") == nil)
    }

    @Test func apiRequestBuildsExpectedURLHeadersAndJSONBody() throws {
        let service = APIService(baseURL: "https://api.example.test/")
        let payload = SupportContactRequest(
            name: "Avery Notary",
            email: "avery@example.com",
            topic: "Invoices",
            subject: "Question",
            message: "Need help with an invoice.",
            sourcePage: "Profile"
        )

        let request = try service.makeRequest(
            path: "/api/support/contact",
            method: "POST",
            token: "access-token",
            body: service.encodedBody(payload)
        )

        #expect(request.url?.absoluteString == "https://api.example.test/api/support/contact")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-token")
        #expect(request.value(forHTTPHeaderField: "Origin") == "https://api.example.test")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

        let object = try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? [String: Any]
        #expect(object?["email"] as? String == "avery@example.com")
        #expect(object?["sourcePage"] as? String == "Profile")
    }
}
#endif

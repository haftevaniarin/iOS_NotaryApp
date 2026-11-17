import Foundation
import Testing

@testable import notaryledger_ios

@MainActor struct PaymentTermsDefaultsTests {
    private func payload(date: String = "2026-11-16") -> SigningOrderPayload {
        SigningOrderPayload(
            customerName: "Title", payerName: nil, signerName: "Signer", signingType: nil,
            date: date, time: nil, fee: 150, notarialActFee: 0, paid: false, paidDate: nil,
            invoiceNumber: "TERMS-1", notes: nil, mileage: nil, travelFee: nil, status: .scheduled)
    }

    @Test func defaultsPersistPerAccountAndCanBeRemoved() throws {
        let suite = "payment-terms-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SigningPaymentDefaults(defaults: defaults)
        #expect(store.days(for: "account-a") == nil)
        store.save(days: 30, for: "account-a")
        #expect(SigningPaymentDefaults(defaults: defaults).days(for: "account-a") == 30)
        #expect(store.days(for: "account-b") == nil)
        store.save(days: 15, for: "account-b")
        store.save(days: nil, for: "account-a")
        #expect(store.days(for: "account-a") == nil)
        #expect(store.days(for: "account-b") == 15)
        #expect(store.applying(to: payload(), ownerID: "account-a").dueDate == .unchanged)
    }

    @Test func defaultsUseSigningCalendarDaysIncludingLeapYearsAndUTCOffsets() throws {
        let suite = "payment-terms-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SigningPaymentDefaults(defaults: defaults)
        store.save(days: 30, for: "owner")
        #expect(store.applying(to: payload(), ownerID: "owner").dueDate == .set("2026-12-16"))
        #expect(store.applying(to: payload(date: "2026-11-16T23:30:00-08:00"), ownerID: "owner").dueDate == .set("2026-12-17"))
        #expect(store.applying(to: payload(date: "2024-02-28"), ownerID: "owner").dueDate == .set("2024-03-29"))
        #expect(store.applying(to: payload(date: "2026-03-08"), ownerID: "owner").dueDate == .set("2026-04-07"))
        store.save(days: 0, for: "owner")
        #expect(store.applying(to: payload(), ownerID: "owner").dueDate == .set("2026-11-16"))
        #expect(store.applying(to: payload(date: "invalid"), ownerID: "owner").dueDate == .unchanged)
        #expect(store.applying(to: payload(), ownerID: nil).dueDate == .unchanged)
    }

    @Test func inputAcceptsWholeDayTermsAndPreservesExplicitPayloadDates() throws {
        #expect(SigningPaymentDefaults.parse("30") == 30)
        #expect(SigningPaymentDefaults.parse(" 0 ") == 0)
        for invalid in ["", "-1", "1.5", "abc", "366"] { #expect(SigningPaymentDefaults.parse(invalid) == nil) }
        let suite = "payment-terms-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SigningPaymentDefaults(defaults: defaults)
        store.save(days: 30, for: "owner")
        var explicit = payload()
        explicit.dueDate = .set("2026-12-31")
        #expect(store.applying(to: explicit, ownerID: "owner").dueDate == .set("2026-12-31"))
        let imported = SigningOrder(
            id: "imported", customerName: "Title", signerName: "Signer", date: "2026-11-16T20:00:00Z",
            fee: 150, paid: false, invoiceNumber: "TERMS-1", mileage: 25)
        let prepared = try #require(store.applying(to: imported, ownerID: "owner"))
        #expect(prepared.dueDate == .set("2026-12-16"))
        #expect(prepared.preserveMileage && prepared.date == imported.date && prepared.time == nil)
        let timed = SigningOrder(
            id: "timed", customerName: "Title", signerName: "Signer", date: "2026-11-16", time: "14:30",
            fee: 150, paid: false, invoiceNumber: "TERMS-2")
        #expect(store.applying(to: timed, ownerID: "owner")?.time == "14:30")
        var dated = imported
        dated.dueDate = "2026-12-31"
        #expect(store.applying(to: dated, ownerID: "owner") == nil)
    }
}

extension ValidationAndAPITests {
    @Test func creationUsesProfileTermsAndEditsOmitDueDate() async throws {
        let previousUser = SessionStorage.getCurrentUser()
        let previousToken = SessionStorage.getAccessToken()
        let owner = "payment-terms-api-\(UUID())"
        SessionStorage.saveCurrentUser(AuthUser(id: owner, fullName: "Terms user", email: "terms@example.test"))
        SessionStorage.saveAccessToken("fixture")
        SigningPaymentDefaults().save(days: 30, for: owner)
        defer {
            SigningPaymentDefaults().save(days: nil, for: owner)
            if let previousUser { SessionStorage.saveCurrentUser(previousUser) } else { SessionStorage.clearCurrentUser() }
            if let previousToken { SessionStorage.saveAccessToken(previousToken) } else { SessionStorage.clearTokens() }
            MockURLProtocol.requestHandler = nil
        }
        MockURLProtocol.requestHandler = { request in
            if request.url?.path == "/api/config/maintenance" {
                return MockURLProtocol.jsonResponse(for: request, body: #"{"enabled":false}"#)
            }
            let object = try #require(JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
            #expect(object["invoiceNumber"] as? String == "TERMS-1")
            if request.httpMethod == "POST" {
                #expect(object["dueDate"] as? String == "2026-12-16")
            } else {
                #expect(object["dueDate"] == nil)
            }
            return MockURLProtocol.jsonResponse(
                for: request, body: #"{"id":"new","date":"2026-11-16","dueDate":"2026-12-16","paymentStatus":"Pending","paid":false}"#)
        }
        let api = APIService(baseURL: "https://terms.example.test", session: MockURLProtocol.session())
        let payload = SigningOrderPayload(
            customerName: "Title", payerName: nil, signerName: "Signer", signingType: nil,
            date: "2026-11-16", time: nil, fee: 150, notarialActFee: 0, paid: false, paidDate: nil,
            invoiceNumber: "TERMS-1", notes: nil, mileage: nil, travelFee: nil, status: .scheduled)
        let created = try await api.createOrder(payload)
        #expect(created.dueDate == "2026-12-16")
        SigningPaymentDefaults().save(days: 15, for: owner)
        let updated = try await api.updateOrder(orderId: "new", order: payload)
        #expect(updated.dueDate == "2026-12-16")
    }

    @Test func spreadsheetDefaultsPreserveDatedOrdersAndReportPartialFailure() async throws {
        let previousUser = SessionStorage.getCurrentUser()
        let previousToken = SessionStorage.getAccessToken()
        let owner = "payment-terms-import-\(UUID())"
        SessionStorage.saveCurrentUser(AuthUser(id: owner, fullName: "Terms user", email: "terms@example.test"))
        SessionStorage.saveAccessToken("fixture")
        SigningPaymentDefaults().save(days: 30, for: owner)
        defer {
            SigningPaymentDefaults().save(days: nil, for: owner)
            if let previousUser { SessionStorage.saveCurrentUser(previousUser) } else { SessionStorage.clearCurrentUser() }
            if let previousToken { SessionStorage.saveAccessToken(previousToken) } else { SessionStorage.clearTokens() }
            MockURLProtocol.requestHandler = nil
        }
        for fail in [false, true] {
            MockURLProtocol.requestHandler = { request in
                switch request.url?.path {
                case "/api/config/maintenance": return MockURLProtocol.jsonResponse(for: request, body: #"{"enabled":false}"#)
                case "/api/orders/import":
                    return MockURLProtocol.jsonResponse(
                        for: request,
                        body:
                            #"{"importedCount":2,"skippedDuplicateCount":0,"orders":[{"id":"new","customerName":"Title","signerName":"Signer","date":"2026-11-16","fee":150,"invoiceNumber":"TERMS-1"},{"id":"dated","date":"2026-11-16","dueDate":"2026-12-31"}]}"#
                    )
                case "/api/orders/new":
                    let object = try #require(JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
                    #expect(object["dueDate"] as? String == "2026-12-16")
                    #expect(object["invoiceNumber"] as? String == "TERMS-1")
                    #expect(object["miles"] == nil && object["parkingFee"] == nil)
                    if fail { throw URLError(.notConnectedToInternet) }
                    return MockURLProtocol.jsonResponse(
                        for: request, body: #"{"id":"new","date":"2026-11-16","dueDate":"2026-12-16","paymentStatus":"Pending"}"#)
                default:
                    Issue.record("Only newly imported signings without a due date should be updated")
                    return MockURLProtocol.jsonResponse(for: request, body: "{}")
                }
            }
            let result = try await APIService(baseURL: "https://terms.example.test", session: MockURLProtocol.session())
                .importSignings(
                    MultipartFile(
                        fieldName: "file", fileName: "signings.csv", mimeType: "text/csv", data: Data("Customer,Signer,Date,Fee".utf8)))
            #expect(result.importedCount == 2 && result.orders.count == 2)
            #expect(result.orders[1].dueDate == "2026-12-31")
            #expect(result.paymentTermsFailureCount == (fail ? 1 : 0))
            if !fail { #expect(result.orders[0].dueDate == "2026-12-16") }
        }
    }
}

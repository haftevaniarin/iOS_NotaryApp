import Foundation
import Testing
@testable import notaryledger_ios

extension ValidationAndAPITests {
    @Test func stripeInvoiceHistoryPaginatesWithoutDuplicates() async throws {
        let previous = SessionStorage.getAccessToken(); SessionStorage.saveAccessToken("stripe-history-fixture")
        defer { endStripeFixture(previous) }
        MockURLProtocol.requestHandler = { request in
            switch request.url?.path {
            case "/api/config/maintenance": return MockURLProtocol.jsonResponse(for: request, body: #"{"enabled":false}"#)
            case "/api/billing/usage": return MockURLProtocol.jsonResponse(for: request, body: #"{"usage":{"signingsLogged":7,"invoicesSent":2,"signingLimit":20,"remainingFreeOrders":13,"hasExternalSubscription":false}}"#)
            default:
                let cursor = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value
                let one = #"{"id":"in_one","date":"2026-11-01T12:00:00.000Z","status":"paid","amountMinor":799,"paidMinor":799,"currency":"usd"}"#
                let two = #"{"id":"in_two","date":"2026-10-01T12:00:00.000Z","status":"paid","amountMinor":799,"paidMinor":799,"currency":"usd"}"#
                let body = cursor == nil ? "{\"history\":{\"items\":[\(one)],\"nextCursor\":\"in_one\"}}" : "{\"history\":{\"items\":[\(one),\(two)],\"nextCursor\":null}}"
                return MockURLProtocol.jsonResponse(for: request, body: body)
            }
        }
        let model = BillingOverviewModel(service: AccountBillingService(api: APIService(baseURL: "https://stripe-history.example.test", session: MockURLProtocol.session())))
        await model.load(accountID: "owner")
        #expect(model.snapshot?.invoices.count == 1 && model.snapshot?.nextCursor == "in_one")
        await model.loadMoreInvoices(accountID: "other-owner")
        #expect(model.snapshot?.invoices.count == 1)
        await model.loadMoreInvoices(accountID: "owner")
        #expect(model.snapshot?.invoices.map(\.id) == ["in_one", "in_two"])
        #expect(model.snapshot?.nextCursor == nil)
    }
    private func stripeFixtureAccount(paid: Bool) throws -> String {
        var object = try #require(JSONSerialization.jsonObject(with: Data(SubscriptionTestFixture.account.utf8)) as? [String: Any])
        object["card"] = NSNull(); object["billingDetails"] = NSNull()
        if !paid {
            object["billing"] = ["plan": "FREE", "active": false, "isPro": false, "subscriptionStatus": "NONE"]
            object["currentPrice"] = NSNull(); object["currentPlanID"] = "free"; object["hasSubscription"] = false
            object["renewalDate"] = NSNull()
        }
        return String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }
    private func endStripeFixture(_ token: String?) {
        MockURLProtocol.requestHandler = nil; MockURLProtocol.requests = []
        if let token { SessionStorage.saveAccessToken(token) } else { SessionStorage.clearTokens() }
    }
    @Test func stripeOnlyCheckoutUsesServerPricingAndDoesNotGrantAccessFromCheckoutURL() async throws {
        let previous = SessionStorage.getAccessToken(); SessionStorage.saveAccessToken("stripe-only-fixture")
        let suite = "stripe-only-\(UUID())", defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); endStripeFixture(previous) }
        var paid = false
        let freeBody = try stripeFixtureAccount(paid: false), proBody = try stripeFixtureAccount(paid: true)
        MockURLProtocol.requestHandler = { request in
            switch request.url?.path {
            case "/api/config/maintenance": return MockURLProtocol.jsonResponse(for: request, body: #"{"enabled":false}"#)
            case "/api/stripe/subscription-account":
                #expect(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.contains(URLQueryItem(name: "view", value: "subscription")) == true)
                return MockURLProtocol.jsonResponse(for: request, body: SubscriptionTestFixture.response(paid ? proBody : freeBody))
            case "/api/stripe/checkout-session":
                let data = try #require(request.httpBody)
                let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: String])
                #expect(body["clientType"] == "ios" && body["billingInterval"] == "annual")
                #expect(body["priceID"] == nil && body["returnURL"] == nil)
                return MockURLProtocol.jsonResponse(for: request, body: #"{"checkoutSession":{"id":"cs_test_stripe_only","url":"https://checkout.stripe.com/c/pay/test"}}"#)
            default:
                #expect(request.url?.path == "/api/stripe/sync-checkout-session")
                return MockURLProtocol.jsonResponse(for: request, body: #"{"billing":{"plan":"FREE","active":false}}"#)
            }
        }
        let api = APIService(baseURL: "https://stripe-only.example.test", session: MockURLProtocol.session())
        let store = SubscriptionStore(accountID: "owner", api: api, defaults: defaults, country: { "USA" })
        await store.refresh()
        #expect(store.currentTier == .free && store.canUseStripe)
        #expect(store.priceData(for: .pro, interval: .annual)?.amountMinor == 8999)
        #expect(store.account?.card == nil)
        let url = await store.beginPlan(.pro, interval: .annual)
        #expect(url?.host == "checkout.stripe.com")
        #expect(store.billingStatus?.hasProAccess == false)
        #expect(defaults.string(forKey: "notary_pending_checkout_owner") == "owner")
        paid = true
        await store.refresh()
        #expect(store.currentTier == .pro && store.billingStatus?.hasProAccess == true)
        #expect(defaults.string(forKey: "notary_pending_checkout") == nil)
        store.bind(accountID: "different-owner")
        #expect(store.account == nil && store.currentTier == .free && !store.canUseStripe)
    }
    @Test func stripeOnlyIntervalChangeRequiresReviewedPreviewAndUsesOwnedPortalSession() async throws {
        let previous = SessionStorage.getAccessToken(); SessionStorage.saveAccessToken("stripe-only-fixture")
        defer { endStripeFixture(previous) }
        let account = try stripeFixtureAccount(paid: true)
        MockURLProtocol.requestHandler = { request in
            switch request.url?.path {
            case "/api/config/maintenance": return MockURLProtocol.jsonResponse(for: request, body: #"{"enabled":false}"#)
            case "/api/stripe/subscription-account": return MockURLProtocol.jsonResponse(for: request, body: SubscriptionTestFixture.response(account))
            case "/api/stripe/change-preview": return MockURLProtocol.jsonResponse(for: request, body: "{\"preview\":\(SubscriptionTestFixture.preview)}")
            case "/api/stripe/change-interval":
                let data = try #require(request.httpBody)
                let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
                #expect(body["expectedAmountMinor"] as? Int == 8999)
                #expect(body["expectedCurrency"] as? String == "usd")
                return MockURLProtocol.jsonResponse(for: request, body: #"{"billing":{"plan":"PRO","active":true}}"#)
            default:
                #expect(request.url?.path == "/api/stripe/customer-portal-session")
                let data = try #require(request.httpBody)
                let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: String])
                #expect(body["clientType"] == "ios" && body["action"] == "cancel")
                #expect(body["customer"] == nil && body["subscription"] == nil)
                return MockURLProtocol.jsonResponse(for: request, body: #"{"portalSession":{"id":"bps_test","url":"https://billing.stripe.com/p/test"}}"#)
            }
        }
        let store = SubscriptionStore(accountID: "owner", api: APIService(baseURL: "https://stripe-only.example.test", session: MockURLProtocol.session()), country: { "USA" })
        await store.refresh()
        #expect(await store.beginPlan(.pro, interval: .annual) == nil)
        let preview = try #require(store.changePreview)
        #expect(preview.amountDueNowMinor == 0 && preview.prorationBehavior == "none")
        #expect(!MockURLProtocol.requests.contains { $0.url?.path == "/api/stripe/change-interval" })
        try await store.confirmChange(preview)
        #expect(store.changePreview == nil)
        #expect(await store.beginPlan(.free, interval: .monthly)?.host == "billing.stripe.com")
        #expect(!MockURLProtocol.requests.contains { $0.url?.path == "/api/stripe/checkout-session" })
    }
    @Test func stripeOnlyUnknownOrNonUSStorefrontCannotStartBillingActions() async throws {
        let previous = SessionStorage.getAccessToken(); SessionStorage.saveAccessToken("stripe-only-fixture")
        defer { endStripeFixture(previous) }
        let account = try stripeFixtureAccount(paid: false)
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(for: request, body: request.url?.path == "/api/config/maintenance" ? #"{"enabled":false}"# : SubscriptionTestFixture.response(account))
        }
        for country in [nil, "CAN"] as [String?] {
            let store = SubscriptionStore(accountID: "owner", api: APIService(baseURL: "https://stripe-only.example.test", session: MockURLProtocol.session()), country: { country })
            await store.refresh()
            #expect(!store.canUseStripe)
            #expect(await store.beginPlan(.pro, interval: .annual) == nil)
            #expect(store.error != nil)
        }
        #expect(!MockURLProtocol.requests.contains { $0.httpMethod == "POST" })
    }
}

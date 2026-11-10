import Foundation
import Testing
@testable import notaryledger_ios

nonisolated enum SubscriptionTestFixture {
    static let account = #"""
    {"billing":{"plan":"PRO","isPro":true,"active":true,"subscriptionStatus":"ACTIVE","billingInterval":"monthly"},"provider":"stripe","plans":[{"id":"free","name":"Notary Ledger Free","price":null,"features":["20 lifetime signing orders"]},{"id":"monthly","name":"Notary Ledger Pro","price":{"name":"Notary Ledger Pro","amountMinor":899,"currency":"usd","billingInterval":"monthly"},"features":["Unlimited signing orders","Tax reports"]},{"id":"annual","name":"Notary Ledger Pro","price":{"name":"Notary Ledger Pro","amountMinor":8999,"currency":"usd","billingInterval":"annual"},"features":["Unlimited signing orders","Tax reports"]}],"currentPrice":{"name":"Notary Ledger Pro","amountMinor":899,"currency":"usd","billingInterval":"monthly"},"currentPlanID":"monthly","hasSubscription":true,"trialEnd":null,"renewalDate":"2026-12-08T12:00:00.000Z","cancellationDate":null,"pendingUpdate":false,"card":{"brand":"visa","last4":"4242","expMonth":12,"expYear":2030},"billingDetails":{"name":"Avery Notary","email":"avery@example.test","address":{"line1":"123 Sample Street","city":"Los Angeles","state":"CA","postal_code":"90001","country":"US"}},"capabilities":{"manage":true,"paymentMethod":true,"billingDetails":true,"cancel":true,"resume":false,"history":true},"paymentIssue":null,"history":{"items":[{"id":"in_one","number":"SUB-001","date":"2026-11-08T12:00:00.000Z","status":"paid","amountMinor":899,"paidMinor":899,"currency":"usd","receiptURL":"https://invoice.stripe.com/i/one","paymentURL":null}],"nextCursor":"in_one"}}
    """#
    static let preview = #"""
    {"billingInterval":"annual","targetPrice":{"name":"Notary Ledger Pro","amountMinor":8999,"currency":"usd","billingInterval":"annual"},"effectiveAt":"2026-12-08T12:00:00.000Z","amountDueNowMinor":0,"prorationBehavior":"none","expectedCurrentPeriodEnd":"2026-12-08T12:00:00.000Z","expectedAmountMinor":8999,"expectedCurrency":"usd"}
    """#
    static func response(_ account: String = account) -> String { "{\"success\":true,\"data\":{\"account\":\(account)}}" }
}

@MainActor
struct SubscriptionBillingValueTests {
    @Test func storefrontAndAppleSubscriptionsDeterminePurchaseEligibility() {
        for country in [nil, "CAN", "GBR", "US"] {
            let policy = SubscriptionEligibility(countryCode: country)
            #expect(!policy.allowsStripeLinks && !policy.allowsNewStripePurchase(hasStripeSubscription: false))
        }
        let us = SubscriptionEligibility(countryCode: "USA")
        #expect(us.allowsStripeLinks && us.allowsNewStripePurchase(hasStripeSubscription: false))
        #expect(!us.allowsNewStripePurchase(hasStripeSubscription: true))
        let apple = SubscriptionEligibility(countryCode: "USA", hasAppleSubscription: true)
        #expect(!apple.allowsNewStripePurchase(hasStripeSubscription: false))
    }
    @Test func moneyDatesAndBillingLinksUseActualValuesAndTrustedOrigins() {
        #expect(SubscriptionFormatting.money(899, currency: "usd").contains("8.99"))
        #expect(!SubscriptionFormatting.money(899, currency: "jpy").contains("8.99"))
        #expect(SubscriptionFormatting.money(1234, currency: "kwd").contains("1.234"))
        #expect(SubscriptionFormatting.date("2026-12-08T12:00:00.000Z") != "Not available")
        #expect(SubscriptionFormatting.date("ambiguous") == "Not available")
        for link in ["http://billing.stripe.com/a", "https://stripe.com.evil.example/a", "https://evilstripe.com/a", "https://user@billing.stripe.com/a", "https://billing.stripe.com:444/a", "javascript:alert(1)"] {
            #expect(SubscriptionFormatting.trustedURL(link) == nil)
        }
        #expect(SubscriptionFormatting.trustedURL("https://billing.stripe.com/p/session") != nil)
    }
    @Test func subscriptionDetailsDecodeCardBillingAddressAndReceipts() throws {
        let account = try JSONDecoder().decode(SubscriptionAccount.self, from: Data(SubscriptionTestFixture.account.utf8))
        #expect(account.currentPrice?.amountMinor == 899 && account.plans.last?.price?.amountMinor == 8999)
        #expect(account.card?.last4 == "4242" && account.card?.expYear == 2030)
        #expect(account.billingDetails?.address?.display.contains("90001") == true)
        #expect(account.history.items.first?.status == "paid")
        #expect(account.billing.hasProAccess && !account.pendingUpdate)
    }
}

extension ValidationAndAPITests {
    private func subscriptionFixtureEnd(_ token: String?) {
        MockURLProtocol.requestHandler = nil; MockURLProtocol.requests = []
        if let token { SessionStorage.saveAccessToken(token) } else { SessionStorage.clearTokens() }
    }
    @Test func subscriptionAPIAuthenticatesScopesHistoryAndConfirmsTheReviewedPrice() async throws {
        let previous = SessionStorage.getAccessToken(); SessionStorage.saveAccessToken("subscription-fixture")
        defer { subscriptionFixtureEnd(previous) }
        MockURLProtocol.requestHandler = { request in
            if request.url?.path == "/api/config/maintenance" { return MockURLProtocol.jsonResponse(for: request, body: #"{"enabled":false}"#) }
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer subscription-fixture")
            switch request.url?.path {
            case "/api/stripe/subscription-account": return MockURLProtocol.jsonResponse(for: request, body: SubscriptionTestFixture.response())
            case "/api/stripe/subscription-payments":
                #expect(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "in_one")
                return MockURLProtocol.jsonResponse(for: request, body: #"{"history":{"items":[],"nextCursor":null}}"#)
            case "/api/stripe/change-preview": return MockURLProtocol.jsonResponse(for: request, body: "{\"preview\":\(SubscriptionTestFixture.preview)}")
            case "/api/stripe/change-interval":
                let data = try #require(request.httpBody)
                let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
                #expect(body["billingInterval"] as? String == "annual")
                #expect(body["expectedAmountMinor"] as? Int == 8999)
                #expect(body["expectedCurrency"] as? String == "usd")
                #expect(body["expectedCurrentPeriodEnd"] as? String == "2026-12-08T12:00:00.000Z")
                return MockURLProtocol.jsonResponse(for: request, body: #"{"billing":{"plan":"PRO","active":true,"scheduledChange":{"billingInterval":"annual","effectiveAt":"2026-12-08T12:00:00.000Z"}}}"#)
            default:
                let data = try #require(request.httpBody)
                let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: String])
                #expect(body["action"] == "cancel" && body["clientType"] == "ios")
                #expect(body["customer"] == nil && body["subscription"] == nil)
                return MockURLProtocol.jsonResponse(for: request, body: #"{"portalSession":{"id":"bps_one","url":"https://billing.stripe.com/p/one"}}"#)
            }
        }
        let api = APIService(baseURL: "https://subscription.example.test", session: MockURLProtocol.session())
        #expect(try await api.fetchSubscriptionAccount().currentPlanID == "monthly")
        #expect(try await api.fetchSubscriptionHistory(cursor: "in_one").items.isEmpty)
        let preview = try await api.previewSubscriptionInterval("annual")
        #expect(try await api.confirmSubscriptionInterval(preview).scheduledChange?.billingInterval == "annual")
        #expect(try await api.createCustomerPortalSession(action: "cancel").sessionId == "bps_one")
    }
    @Test func failedCheckoutSynchronizationStillLoadsSubscriptionAndDoesNotGrantAccess() async throws {
        let previous = SessionStorage.getAccessToken(); SessionStorage.saveAccessToken("subscription-fixture")
        let suite = "subscription-test-\(UUID())", defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); subscriptionFixtureEnd(previous) }
        defaults.set("owner", forKey: "notary_pending_checkout_owner"); defaults.set("cs_old", forKey: "notary_pending_checkout")
        let free = SubscriptionTestFixture.account.replacingOccurrences(of: #""plan":"PRO","isPro":true,"active":true"#, with: #""plan":"FREE","isPro":false,"active":false"#).replacingOccurrences(of: #""hasSubscription":true"#, with: #""hasSubscription":false"#)
        MockURLProtocol.requestHandler = { request in
            if request.url?.path == "/api/config/maintenance" { return MockURLProtocol.jsonResponse(for: request, body: #"{"enabled":false}"#) }
            if request.url?.path == "/api/stripe/sync-checkout-session" { return MockURLProtocol.jsonResponse(for: request, statusCode: 400, body: #"{"message":"Checkout expired"}"#) }
            return MockURLProtocol.jsonResponse(for: request, body: SubscriptionTestFixture.response(free))
        }
        let model = SubscriptionBillingModel(api: APIService(baseURL: "https://subscription.example.test", session: MockURLProtocol.session()), defaults: defaults)
        let billing = await model.load(owner: "owner")
        #expect(billing?.hasProAccess == false && model.account != nil && !model.error.isEmpty)
        #expect(model.pendingCheckout && !model.isLoading)
        _ = await model.load(owner: "other")
        #expect(!model.pendingCheckout)
    }
    @Test func subscriptionModelPreservesKnownDetailsOnErrorsAndClearsThemBetweenAccounts() async throws {
        let previous = SessionStorage.getAccessToken(); SessionStorage.saveAccessToken("subscription-fixture")
        defer { subscriptionFixtureEnd(previous) }
        var failing = false
        MockURLProtocol.requestHandler = { request in
            if request.url?.path == "/api/config/maintenance" { return MockURLProtocol.jsonResponse(for: request, body: #"{"enabled":false}"#) }
            return MockURLProtocol.jsonResponse(for: request, statusCode: failing ? 503 : 200, body: failing ? #"{"message":"Unavailable"}"# : SubscriptionTestFixture.response())
        }
        let model = SubscriptionBillingModel(api: APIService(baseURL: "https://subscription.example.test", session: MockURLProtocol.session()))
        _ = await model.load(owner: "first"); #expect(model.account != nil)
        failing = true
        _ = await model.load(owner: "first"); #expect(model.account != nil && !model.error.isEmpty)
        _ = await model.load(owner: "second"); #expect(model.account == nil && model.history.items.isEmpty)
    }
    @Test func subscriptionHistoryDeduplicatesAndBlockedStorefrontsNeverCreateSessions() async throws {
        let previous = SessionStorage.getAccessToken(); SessionStorage.saveAccessToken("subscription-fixture")
        defer { subscriptionFixtureEnd(previous) }
        MockURLProtocol.requests = []
        MockURLProtocol.requestHandler = { request in
            if request.url?.path == "/api/config/maintenance" { return MockURLProtocol.jsonResponse(for: request, body: #"{"enabled":false}"#) }
            if request.url?.path == "/api/stripe/subscription-payments" {
                return MockURLProtocol.jsonResponse(for: request, body: #"{"history":{"items":[{"id":"in_one","amountMinor":899,"paidMinor":899,"currency":"usd"},{"id":"in_two","amountMinor":899,"paidMinor":0,"currency":"usd","status":"open"}],"nextCursor":null}}"#)
            }
            return MockURLProtocol.jsonResponse(for: request, body: SubscriptionTestFixture.response())
        }
        let model = SubscriptionBillingModel(api: APIService(baseURL: "https://subscription.example.test", session: MockURLProtocol.session()))
        _ = await model.load(owner: "owner"); await model.loadMoreHistory(owner: "owner")
        #expect(model.history.items.map(\.id) == ["in_one", "in_two"])
        do { _ = try await model.portal(action: "manage", owner: "owner", eligibility: SubscriptionEligibility(countryCode: "CAN")); Issue.record("Expected storefront rejection") } catch { }
        do { _ = try await model.checkout(interval: "monthly", owner: "owner", eligibility: SubscriptionEligibility(countryCode: "USA")); Issue.record("Expected duplicate rejection") } catch { }
        #expect(!MockURLProtocol.requests.contains { $0.httpMethod == "POST" })
    }
}

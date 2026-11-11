import Foundation
import Testing
@testable import notaryledger_ios

@MainActor
struct BillingReturnTests {
    @Test func parsesUniversalAndCustomCheckoutPortalAndCancelReturns() throws {
        for base in ["https://notaryledger.org/mobile-billing-return.html", "https://www.notaryledger.org/mobile-billing-return.html", "notaryledger://billing/return"] {
            let success = try #require(BillingReturnLink(url: URL(string: base + "?flow=checkout&checkout=success&session_id=cs_test_123")!))
            #expect(success.outcome == .checkoutSuccess && success.sessionID == "cs_test_123")
            #expect(BillingReturnLink(url: URL(string: base + "?flow=portal")!)?.outcome == .portal)
            #expect(BillingReturnLink(url: URL(string: base + "?flow=checkout&checkout=canceled")!)?.outcome == .checkoutCancelled)
        }
    }

    @Test func rejectsUnexpectedOriginsPathsAndAmbiguousQueryParameters() {
        for value in [
            "http://notaryledger.org/mobile-billing-return.html?flow=portal",
            "https://evil.example/mobile-billing-return.html?flow=portal",
            "https://notaryledger.org.evil.example/mobile-billing-return.html?flow=portal",
            "https://user@notaryledger.org/mobile-billing-return.html?flow=portal",
            "notaryledger://billing/unrelated?flow=portal",
            "notaryledger://billing/return?flow=portal&flow=checkout",
            "notaryledger://billing/return?flow=checkout&checkout=paid"
        ] { #expect(BillingReturnLink(url: URL(string: value)!) == nil) }
        #expect(BillingReturnLink(url: URL(string: "notaryledger://billing/return?flow=checkout&checkout=success&session_id=https://evil.example")!)?.sessionID == nil)
    }

    @Test func appBundleRegistersItsFallbackSchemeAndUniversalLinkDomains() throws {
        let types = try #require(Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]])
        #expect(types.contains { ($0["CFBundleURLSchemes"] as? [String])?.contains("notaryledger") == true })
    }
}

extension ValidationAndAPITests {
    @Test func nativeBillingSessionRequestsIdentifyIOSWithoutSupplyingRedirectURLs() async throws {
        let previous = SessionStorage.getAccessToken()
        SessionStorage.saveAccessToken("billing-return-fixture")
        defer {
            MockURLProtocol.requestHandler = nil; MockURLProtocol.requests = []
            if let previous { SessionStorage.saveAccessToken(previous) } else { SessionStorage.clearTokens() }
        }
        MockURLProtocol.requestHandler = { request in
            if request.url?.path == "/api/config/maintenance" { return MockURLProtocol.jsonResponse(for: request, body: #"{"enabled":false}"#) }
            let body = try JSONSerialization.jsonObject(with: #require(request.httpBody)) as? [String: String]
            #expect(body?["clientType"] == "ios")
            #expect(body?["returnUrl"] == nil && body?["successUrl"] == nil && body?["cancelUrl"] == nil)
            if request.url?.path == "/api/stripe/checkout-session" {
                #expect(body?["billingInterval"] == "annual")
                return MockURLProtocol.jsonResponse(for: request, body: #"{"checkoutSession":{"id":"cs_test_123","url":"https://checkout.stripe.test/123"}}"#)
            }
            #expect(request.url?.path == "/api/stripe/customer-portal-session")
            return MockURLProtocol.jsonResponse(for: request, body: #"{"portalSession":{"id":"bps_test_123","url":"https://billing.stripe.test/123"}}"#)
        }
        let api = APIService(baseURL: "https://billing-return.example.test", session: MockURLProtocol.session())
        #expect(try await api.createCheckoutSession(billingInterval: "annual").sessionId == "cs_test_123")
        #expect(try await api.createCustomerPortalSession().url == "https://billing.stripe.test/123")
    }

    @Test func billingReturnsPreserveDestinationDuringSessionRestorationAndNeverGrantProFromURL() async throws {
        let previousUser = SessionStorage.getCurrentUser()
        let previousToken = SessionStorage.getAccessToken()
        let previousRefresh = SessionStorage.getRefreshToken()
        let previousCheckout = UserDefaults.standard.string(forKey: "notary_pending_checkout")
        let previousOwner = UserDefaults.standard.string(forKey: "notary_pending_checkout_owner")
        defer {
            MockURLProtocol.requestHandler = nil; MockURLProtocol.requests = []
            SessionStorage.clearTokens()
            if let previousToken {
                var saved = AuthResponse(token: previousToken)
                saved.refreshToken = previousRefresh
                SessionStorage.saveSession(saved)
            }
            if let previousUser { SessionStorage.saveCurrentUser(previousUser) } else { SessionStorage.clearCurrentUser() }
            UserDefaults.standard.set(previousCheckout, forKey: "notary_pending_checkout")
            UserDefaults.standard.set(previousOwner, forKey: "notary_pending_checkout_owner")
        }
        var saved = AuthResponse(token: "billing-return-fixture", user: AuthUser(id: "billing-owner", fullName: "Avery", email: "avery@example.test"))
        saved.refreshToken = "billing-return-refresh"
        SessionStorage.saveSession(saved)
        MockURLProtocol.requestHandler = { request in
            let body: String
            switch request.url?.path {
            case "/api/config/maintenance": body = #"{"enabled":false}"#
            case "/api/auth/refresh": body = #"{"accessToken":"billing-return-fixture","refreshToken":"billing-return-refresh"}"#
            case "/api/auth/me": body = #"{"id":"billing-owner","fullName":"Avery","email":"avery@example.test"}"#
            case "/api/stripe/billing-status": body = #"{"billing":{"plan":"FREE","active":false}}"#
            default: body = "[]"
            }
            return MockURLProtocol.jsonResponse(for: request, body: body)
        }
        let api = APIService(baseURL: "https://billing-return.example.test", session: MockURLProtocol.session())
        let state = AppState(api: api)
        UserDefaults.standard.set("cs_test_pending", forKey: "notary_pending_checkout")
        UserDefaults.standard.set("billing-owner", forKey: "notary_pending_checkout_owner")
        state.openURL(URL(string: "notaryledger://billing/return?flow=checkout&checkout=success&session_id=cs_test_untrusted&plan=PRO")!)
        #expect(state.billingReturnRevision == 1)
        #expect(UserDefaults.standard.string(forKey: "notary_pending_checkout") == "cs_test_pending")
        await state.boot()
        #expect(state.selectedSection == .billing)
        #expect(state.billingStatus?.hasProAccess == false)
        state.openURL(URL(string: "notaryledger://billing/return?flow=checkout&checkout=canceled")!)
        #expect(state.billingReturnRevision == 2)
        #expect(UserDefaults.standard.string(forKey: "notary_pending_checkout") == nil)
        UserDefaults.standard.set("other-owner", forKey: "notary_pending_checkout_owner")
        UserDefaults.standard.set("cs_other_pending", forKey: "notary_pending_checkout")
        state.openURL(URL(string: "notaryledger://billing/return?flow=checkout&checkout=canceled")!)
        #expect(UserDefaults.standard.string(forKey: "notary_pending_checkout") == "cs_other_pending")
    }
}

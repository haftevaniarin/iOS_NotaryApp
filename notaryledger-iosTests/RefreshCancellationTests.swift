import Foundation
import Testing
@testable import notaryledger_ios

extension ValidationAndAPITests {
    private func refreshState() -> AppState {
        let api = APIService(baseURL: "https://refresh.example.test", session: MockURLProtocol.session())
        let state = AppState(api: api)
        state.currentUser = AuthUser(id: "refresh-owner", fullName: "Avery", email: "avery@example.test")
        state.orders = [SigningOrder(id: "cached-order", customerName: "Cached customer", signerName: "Cached signer", date: "2026-11-01", fee: 100, paid: false)]
        state.expenses = [Expense(id: "cached-expense", date: "2026-11-01", category: "Office supplies", description: "Paper", amount: 20, businessUsePercent: 100)]
        return state
    }

    private func endRefreshFixture(_ previousToken: String?) {
        MockURLProtocol.requestHandler = nil
        MockURLProtocol.requests = []
        if let previousToken { SessionStorage.saveAccessToken(previousToken) } else { SessionStorage.clearTokens() }
    }

    @Test func cancellationUsesErrorTypesRatherThanMatchingUserFacingText() {
        #expect(RequestCancellation.isCancellation(CancellationError()))
        #expect(RequestCancellation.isCancellation(URLError(.cancelled)))
        #expect(RequestCancellation.isCancellation(NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)))
        #expect(!RequestCancellation.isCancellation(URLError(.timedOut)))
        #expect(!RequestCancellation.isCancellation(APIError.serverError("The order was cancelled.")))
    }

    @Test func cancelledLedgerRefreshKeepsCachedDataAndStopsBeforeBillingThenCanRetry() async {
        let previousToken = SessionStorage.getAccessToken()
        SessionStorage.saveAccessToken("refresh-fixture-token")
        defer { endRefreshFixture(previousToken) }
        for cancelledPath in ["/api/orders", "/api/expenses"] {
            let state = refreshState()
            let cachedOrders = state.orders
            let cachedExpenses = state.expenses
            state.updateBillingStatus(BillingStatusPayload(plan: "PRO", active: true), for: "refresh-owner")
            MockURLProtocol.requests = []
            MockURLProtocol.requestHandler = { request in
                if request.url?.path == cancelledPath { throw URLError(.cancelled) }
                return MockURLProtocol.jsonResponse(for: request, body: request.url?.path == "/api/config/maintenance" ? #"{"enabled":false}"# : "[]")
            }
            await state.refreshAll()
            #expect(state.errorMessage.isEmpty && !state.isLoading)
            #expect(state.orders == cachedOrders && state.expenses == cachedExpenses)
            #expect(state.billingStatus?.planLabel == "PRO" && !state.billingLoadFailed)
            #expect(!MockURLProtocol.requests.contains { $0.url?.path == "/api/stripe/billing-status" })
            if cancelledPath == "/api/orders" {
                #expect(!MockURLProtocol.requests.contains { $0.url?.path == "/api/expenses" })
            }

            MockURLProtocol.requestHandler = { request in
                let body = request.url?.path == "/api/stripe/billing-status" ? #"{"billing":{"plan":"FREE","active":false}}"# : "[]"
                return MockURLProtocol.jsonResponse(for: request, body: body)
            }
            await state.refreshAll()
            #expect(state.errorMessage.isEmpty && !state.isLoading)
            #expect(state.orders.isEmpty && state.expenses.isEmpty)
            #expect(state.billingStatus?.planLabel == "FREE")
        }
    }

    @Test func cancellingSwiftTaskDuringExpenseRequestDoesNotPublishPartialDataOrFetchBilling() async {
        let previousToken = SessionStorage.getAccessToken()
        SessionStorage.saveAccessToken("refresh-fixture-token")
        defer { endRefreshFixture(previousToken) }
        let state = refreshState()
        let cachedOrders = state.orders
        let cachedExpenses = state.expenses
        MockURLProtocol.requests = []
        // This task inherits the main actor and starts after the handler is set.
        let refresh = Task { await state.refreshAll() }
        MockURLProtocol.requestHandler = { request in
            switch request.url?.path {
            case "/api/config/maintenance": return MockURLProtocol.jsonResponse(for: request, body: #"{"enabled":false}"#)
            case "/api/orders": return MockURLProtocol.jsonResponse(for: request, body: "[]")
            case "/api/expenses":
                refresh.cancel()
                return MockURLProtocol.jsonResponse(for: request, body: "[]")
            default:
                Issue.record("Cancelled refresh must not start follow-up requests")
                return MockURLProtocol.jsonResponse(for: request, body: "{}")
            }
        }
        await refresh.value
        #expect(refresh.isCancelled)
        #expect(state.errorMessage.isEmpty && !state.isLoading)
        #expect(state.orders == cachedOrders && state.expenses == cachedExpenses)
    }

    @Test func alreadyCancelledRefreshDoesNotStartRequestsOrChangeExistingState() async {
        let previousToken = SessionStorage.getAccessToken()
        SessionStorage.saveAccessToken("refresh-fixture-token")
        defer { endRefreshFixture(previousToken) }
        let state = refreshState()
        state.errorMessage = "A previous connection error."
        MockURLProtocol.requests = []
        MockURLProtocol.requestHandler = { request in
            Issue.record("Already-cancelled work must not start a request")
            return MockURLProtocol.jsonResponse(for: request, body: "{}")
        }
        let refresh = Task {
            await state.refreshAll()
            await state.refreshBillingStatus()
        }
        refresh.cancel()
        await refresh.value
        #expect(MockURLProtocol.requests.isEmpty)
        #expect(state.errorMessage == "A previous connection error.")
        #expect(!state.isLoading)
    }

    @Test func billingCancellationDoesNotMarkPlanUnavailableAndNextAttemptCanLoadIt() async {
        let previousToken = SessionStorage.getAccessToken()
        SessionStorage.saveAccessToken("refresh-fixture-token")
        defer { endRefreshFixture(previousToken) }
        for hasCachedPlan in [false, true] {
            let state = refreshState()
            if hasCachedPlan { state.updateBillingStatus(BillingStatusPayload(plan: "PRO", active: true), for: "refresh-owner") }
            MockURLProtocol.requestHandler = { request in
                if request.url?.path == "/api/stripe/billing-status" { throw URLError(.cancelled) }
                return MockURLProtocol.jsonResponse(for: request, body: #"{"enabled":false}"#)
            }
            await state.refreshBillingStatus()
            #expect(!state.billingLoadFailed && state.errorMessage.isEmpty)
            #expect(state.billingStatus?.planLabel == (hasCachedPlan ? "PRO" : nil))
            MockURLProtocol.requestHandler = { request in
                MockURLProtocol.jsonResponse(for: request, body: #"{"billing":{"plan":"FREE","active":false}}"#)
            }
            await state.refreshBillingStatus()
            #expect(state.billingStatus?.planLabel == "FREE" && !state.billingLoadFailed)
        }
    }

    @Test func genuineRefreshFailuresStillAppearAndKeepCachedData() async {
        let previousToken = SessionStorage.getAccessToken()
        SessionStorage.saveAccessToken("refresh-fixture-token")
        defer { endRefreshFixture(previousToken) }
        let state = refreshState()
        let cachedOrders = state.orders
        let cachedExpenses = state.expenses
        MockURLProtocol.requestHandler = { request in
            if request.url?.path == "/api/config/maintenance" {
                return MockURLProtocol.jsonResponse(for: request, body: #"{"enabled":false}"#)
            }
            if request.url?.path == "/api/orders" { throw URLError(.notConnectedToInternet) }
            return MockURLProtocol.jsonResponse(for: request, body: #"{"billing":{"plan":"PRO","active":true}}"#)
        }
        await state.refreshAll()
        #expect(state.errorMessage == URLError(.notConnectedToInternet).localizedDescription)
        #expect(!state.isLoading)
        #expect(state.orders == cachedOrders && state.expenses == cachedExpenses)
    }
}

import Foundation
import Testing
@testable import notaryledger_ios

extension ValidationAndAPITests {
    @Test func planBadgeUsesActiveAccessBeforeLegacyPlanFields() throws {
        for (json, label) in [
            (#"{"plan":"PRO","isPro":true,"active":false}"#, "FREE"),
            (#"{"plan":"PRO","active":true,"cancelAtPeriodEnd":true}"#, "PRO"),
            (#"{"plan":"PRO","isPro":true}"#, "PRO"),
            (#"{"plan":"FREE","isPro":false}"#, "FREE"),
            (#"{"plan":"PRO"}"#, "PRO")
        ] {
            let status = try JSONDecoder().decode(BillingStatusPayload.self, from: Data(json.utf8))
            #expect(status.planLabel == label)
        }
    }

    @Test func sharedPlanRefreshUpdatesAccessAndDoesNotReplaceKnownPlanOnFailure() async {
        SessionStorage.saveAccessToken("billing-plan-fixture")
        defer { SessionStorage.clearSession(); MockURLProtocol.requestHandler = nil; MockURLProtocol.requests = [] }
        var billingBody = #"{"billing":{"plan":"PRO","active":true}}"#
        var status = 200
        MockURLProtocol.requestHandler = { request in
            if request.url?.path == "/api/config/maintenance" {
                return MockURLProtocol.jsonResponse(for: request, body: #"{"enabled":false}"#)
            }
            #expect(request.url?.path == "/api/stripe/billing-status")
            return MockURLProtocol.jsonResponse(for: request, statusCode: status, body: billingBody)
        }
        let service = APIService(baseURL: "https://plans.example.test", session: MockURLProtocol.session())
        let state = AppState(api: service)
        state.currentUser = AuthUser(id: "owner", fullName: "Avery", email: "avery@example.test")
        status = 500
        await state.refreshBillingStatus()
        #expect(state.billingStatus == nil && state.billingLoadFailed)
        status = 200
        await state.refreshBillingStatus()
        #expect(state.billingStatus?.planLabel == "PRO" && !state.billingLoadFailed)
        status = 500
        await state.refreshBillingStatus()
        #expect(state.billingStatus?.planLabel == "PRO" && !state.billingLoadFailed)
        status = 200; billingBody = #"{"billing":{"plan":"FREE","active":false}}"#
        await state.refreshBillingStatus()
        #expect(state.billingStatus?.planLabel == "FREE")
    }

    @Test func planIsClearedBetweenAccountsAndLateResponsesCannotChangeAnotherUserPlan() {
        let state = AppState()
        let pro = BillingStatusPayload(plan: "PRO", active: true)
        let free = BillingStatusPayload(plan: "FREE", active: false)
        state.currentUser = AuthUser(id: "first", fullName: "First", email: "first@example.test")
        state.updateBillingStatus(pro, for: "first")
        #expect(state.billingStatus?.planLabel == "PRO")
        state.currentUser = AuthUser(id: "second", fullName: "Second", email: "second@example.test")
        #expect(state.billingStatus == nil)
        state.updateBillingStatus(pro, for: "first")
        #expect(state.billingStatus == nil)
        state.updateBillingStatus(free, for: "second")
        #expect(state.billingStatus?.planLabel == "FREE")
        state.signOutLocally()
        #expect(state.billingStatus == nil)
    }
}

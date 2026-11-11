import Foundation
import Testing
@testable import notaryledger_ios

@MainActor
private final class BillingServiceProbe: BillingService {
    nonisolated deinit {}
    var account: SubscriptionAccount
    var failure: APIError?
    var reads = 0
    var intervals: [String] = []
    var portalActions: [String] = []
    var syncs: [String] = []
    init(_ account: SubscriptionAccount) { self.account = account }
    func subscription(subscriptionOnly: Bool) async throws -> SubscriptionAccount {
        reads += 1
        if let failure { throw failure }
        return account
    }
    func checkout(interval: String) async throws -> BillingSession {
        intervals.append(interval)
        return BillingSession(url: "https://checkout.stripe.com/c/pay/fixture", sessionId: "cs_fixture")
    }
    func portal(action: String) async throws -> BillingSession {
        portalActions.append(action)
        return BillingSession(url: "https://billing.stripe.com/p/session/fixture", sessionId: "bps_fixture")
    }
    func syncCheckout(sessionID: String) async throws -> BillingStatusPayload { syncs.append(sessionID); return account.billing }
    func snapshot(accountID: String, month: DateInterval) async throws -> BillingSnapshot { BillingSnapshot(usage: nil, invoices: []) }
}

@MainActor
struct BillingViewModelTests {
    @Test func checkoutUsesSelectedIntervalAndOnlyBackendRefreshConfirmsAccess() async throws {
        let service = BillingServiceProbe(try #require(SubscriptionStore.preview(tier: .free).account))
        let name = "billing-vm-\(UUID())", defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let model = BillingViewModel(store: SubscriptionStore(accountID: "owner", defaults: defaults, service: service, country: { "USA" }))
        await model.refresh()
        #expect(model.selectedInterval == .annual && !model.hasSubscription)
        #expect(model.store.savings() == 17 && model.proPrice.contains("79.99/year"))
        model.selectedInterval = .monthly
        await model.subscribe()
        #expect(service.intervals == ["monthly"])
        #expect(model.browser?.url.host == "checkout.stripe.com" && model.browser?.ownerID == "owner")
        #expect(!model.hasSubscription && !model.canSubscribe)
        service.account = try #require(SubscriptionStore.preview(interval: .monthly).account)
        await model.returnedFromStripe()
        #expect(model.browser == nil && model.hasSubscription && !model.canSubscribe)
        #expect(service.reads == 2 && service.syncs == ["cs_fixture"])
    }
    @Test func scheduledCancellationBlocksSubscriptionAndIntervalSelection() async throws {
        let service = BillingServiceProbe(try #require(SubscriptionStore.preview(interval: .annual, cancellationScheduled: true).account))
        let model = BillingViewModel(store: SubscriptionStore(accountID: "owner", service: service, country: { "USA" }))
        await model.refresh()
        #expect(model.cancellationScheduled && !model.canSelectInterval && !model.canSubscribe)
        #expect(model.stateLabel.hasPrefix("Active until ") && model.billingPrice.contains("79.99/year"))
        #expect(model.cancellationNotice.contains(model.currentPeriodLabel))
        await model.subscribe()
        #expect(service.intervals.isEmpty)
        await model.manage()
        #expect(service.portalActions == ["manage"] && model.browser?.url.host == "billing.stripe.com")
        await model.returnedFromStripe()
        #expect(model.browser == nil && service.reads == 2)
    }
    @Test func retryRecoversWithoutPretendingUnknownAccountIsFree() async throws {
        let service = BillingServiceProbe(try #require(SubscriptionStore.preview(tier: .free).account))
        service.failure = .serverError("Billing is unavailable")
        let model = BillingViewModel(store: SubscriptionStore(accountID: "owner", service: service, country: { "USA" }))
        #expect(model.isInitialLoading)
        await model.refresh()
        #expect(model.subscription == nil && model.error != nil && !model.isInitialLoading)
        #expect(!model.canManage && !model.canSubscribe)
        service.failure = nil
        await model.refresh()
        #expect(model.error == nil && model.planName == "Free" && !model.cancellationScheduled)
        #expect(model.canSubscribe && model.freePrice.contains("0"))
    }
    @Test func displayUsesConfiguredPricesAndNoSubscriptionIsCreatedForPro() async throws {
        let account = try JSONDecoder().decode(SubscriptionAccount.self, from: Data(SubscriptionTestFixture.account.utf8))
        let service = BillingServiceProbe(account)
        let model = BillingViewModel(store: SubscriptionStore(accountID: "owner", service: service, country: { "USA" }))
        await model.refresh()
        #expect(model.proPrice.contains("89.99/year"))
        #expect(model.annualDetail?.contains("7.50/month") == true)
        #expect(model.hasSubscription && !model.canSubscribe && model.canSelectInterval)
        await model.subscribe()
        #expect(service.intervals.isEmpty)
    }
}

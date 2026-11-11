import Foundation
import Observation

nonisolated struct StripeBrowserSession: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let ownerID: String
}

@MainActor @Observable
final class BillingViewModel {
    nonisolated deinit {}
    let store: SubscriptionStore
    var selectedInterval: BillingInterval = .annual
    var browser: StripeBrowserSession?

    init(store: SubscriptionStore) { self.store = store }
    convenience init(accountID: String, service: any BillingService) {
        self.init(store: SubscriptionStore(accountID: accountID, service: service))
    }

    var subscription: SubscriptionAccount? { store.account }
    var isLoading: Bool { store.isLoading }
    var isInitialLoading: Bool { subscription == nil && error == nil }
    var error: String? { store.error }
    var hasSubscription: Bool { store.currentTier == .pro }
    var cancellationScheduled: Bool { subscription?.billing.cancelAtPeriodEnd == true }
    var canSelectInterval: Bool { subscription != nil && !cancellationScheduled && !store.busy }
    var canSubscribe: Bool {
        store.canUseStripe && browser == nil && !hasSubscription && !cancellationScheduled
            && store.priceData(for: .pro, interval: selectedInterval) != nil
    }
    var canManage: Bool { store.canUseStripe && browser == nil && subscription?.capabilities.manage == true }
    var planName: String { hasSubscription ? PlanCatalog.proName : PlanTier.free.definition.name }
    var currentPeriod: String? { subscription?.billing.currentPeriodEnd ?? subscription?.cancellationDate ?? subscription?.renewalDate }
    var currentPeriodLabel: String { Self.dateLabel(currentPeriod) }
    var stateLabel: String {
        guard let subscription else { return "Not available" }
        if subscription.billing.hasProAccess {
            return currentPeriod == nil ? "Active" : "Active until \(currentPeriodLabel)"
        }
        if !hasSubscription { return subscription.billing.subscriptionStatus?.uppercased() == "CANCELED" ? "Subscription canceled" : "No active subscription" }
        return statusLabel.capitalized
    }
    var statusLabel: String {
        guard let billing = subscription?.billing else { return "LOADING" }
        switch billing.subscriptionStatus?.uppercased() {
        case "ACTIVE": return "ACTIVE"
        case "TRIALING": return "TRIALING"
        case "PAST_DUE": return "PAST DUE"
        case "UNPAID": return "UNPAID"
        case "CANCELED": return "CANCELED"
        case "INCOMPLETE", "INCOMPLETE_EXPIRED": return "INCOMPLETE"
        case "PAUSED": return "PAUSED"
        default: return billing.hasProAccess ? "ACTIVE" : "NONE"
        }
    }
    var activeStatus: Bool { statusLabel == "ACTIVE" || statusLabel == "TRIALING" }
    var warningStatus: Bool { ["PAST DUE", "UNPAID", "INCOMPLETE"].contains(statusLabel) }
    var billingPrice: String {
        guard let subscription else { return "Not available" }
        guard hasSubscription else { return freePrice }
        guard let price = subscription.currentPrice else { return "Not available" }
        return Self.priceLabel(price)
    }
    var billingInterval: String? {
        (subscription?.currentPrice?.billingInterval ?? subscription?.billing.billingInterval).flatMap(BillingInterval.init(rawValue:))?.title
    }
    var freePrice: String {
        let currency = store.priceData(for: .pro, interval: selectedInterval)?.currency ?? "usd"
        let formatter = NumberFormatter(); formatter.numberStyle = .currency; formatter.currencyCode = currency.uppercased()
        formatter.minimumFractionDigits = 0; formatter.maximumFractionDigits = 0
        return formatter.string(from: 0) ?? SubscriptionFormatting.money(0, currency: currency)
    }
    var proPrice: String { store.priceData(for: .pro, interval: selectedInterval).map(Self.priceLabel) ?? "Price unavailable" }
    var annualDetail: String? {
        guard selectedInterval == .annual, let price = store.priceData(for: .pro, interval: .annual) else { return nil }
        let monthly = SubscriptionFormatting.money(Int((Double(price.amountMinor) / 12).rounded()), currency: price.currency)
        let savings = store.savings().map { " Save \($0)%." } ?? ""
        return "\(monthly)/month effective monthly.\(savings)"
    }
    var cancellationNotice: String {
        "Your Pro subscription ends \(currentPeriodLabel). Billing interval switching is unavailable while cancellation is scheduled."
    }
    func refresh() async { await store.refresh() }
    func manage() async {
        guard canManage, let owner = store.accountID else { return }
        if let url = await store.portalURL(), store.accountID == owner {
            browser = StripeBrowserSession(url: url, ownerID: owner)
        }
    }
    func subscribe() async {
        guard canSubscribe, let owner = store.accountID else { return }
        if let url = await store.beginPlan(.pro, interval: selectedInterval), store.accountID == owner {
            browser = StripeBrowserSession(url: url, ownerID: owner)
        }
    }
    func returnedFromStripe() async {
        browser = nil
        await refresh()
    }
    private static func priceLabel(_ price: SubscriptionPrice) -> String {
        SubscriptionFormatting.money(price.amountMinor, currency: price.currency) + (price.billingInterval == "annual" ? "/year" : "/month")
    }
    private static func dateLabel(_ value: String?) -> String {
        guard let value, let date = DateParser.date(from: value) else { return "Not available" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

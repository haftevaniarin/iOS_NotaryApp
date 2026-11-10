import Foundation
import Observation
import StoreKit // Storefront verification only; purchases use Stripe.

nonisolated struct CurrentSubscription: Equatable {
    let tier: PlanTier
    let interval: BillingInterval
    let expirationDate: Date?
    let willAutoRenew: Bool?
    let scheduledInterval: BillingInterval?
}

@MainActor @Observable
final class SubscriptionStore {
    nonisolated deinit {}
    private(set) var account: SubscriptionAccount?
    private(set) var accountID: String?
    private(set) var isLoading = false
    private(set) var busy = false
    private(set) var eligibility = SubscriptionEligibility()
    var message: String?
    var error: String?
    var changePreview: SubscriptionIntervalPreview?
    @ObservationIgnored private let client: SubscriptionBillingModel
    @ObservationIgnored private let country: @MainActor () async -> String?
    @ObservationIgnored private var revision = UUID()
    @ObservationIgnored private var operation = UUID()
    #if DEBUG
    private(set) var isPreview = false
    private var previewTier: PlanTier = .pro
    private var previewInterval: BillingInterval = .monthly
    #endif

    init(accountID: String? = nil, api: APIService? = nil, defaults: UserDefaults = .standard, service: (any BillingService)? = nil,
         country: @escaping @MainActor () async -> String? = { await Storefront.current?.countryCode }) {
        self.accountID = accountID; self.country = country
        client = SubscriptionBillingModel(api: api, defaults: defaults, subscriptionOnly: true, service: service)
    }
    var billingStatus: BillingStatusPayload? { account?.billing }
    var currentTier: PlanTier { account.map { $0.hasSubscription || $0.billing.hasProAccess ? .pro : .free } ?? .free }
    var canUseStripe: Bool { eligibility.allowsStripeLinks && accountID != nil && account != nil && !busy && !isLoading }
    var pendingUpdate: Bool { account?.pendingUpdate == true }
    var availabilityMessage: String? {
        !isLoading && account != nil && !eligibility.allowsStripeLinks
            ? "External subscription management is unavailable for this App Store storefront. You can still view your billing information." : nil
    }
    var currentSubscription: CurrentSubscription? {
        guard let account, currentTier == .pro,
              let interval = BillingInterval(rawValue: account.currentPrice?.billingInterval ?? account.billing.billingInterval ?? "") else { return nil }
        return CurrentSubscription(tier: .pro, interval: interval,
            expirationDate: Self.date(account.cancellationDate ?? account.renewalDate ?? account.billing.currentPeriodEnd),
            willAutoRenew: account.cancellationDate != nil ? false : account.renewalDate != nil ? true : nil,
            scheduledInterval: account.billing.scheduledChange?.billingInterval.flatMap(BillingInterval.init(rawValue:)))
    }
    func bind(accountID: String?) {
        guard self.accountID != accountID else { return }
        self.accountID = accountID; revision = UUID(); operation = UUID()
        account = nil; changePreview = nil; message = nil; error = nil; busy = false; isLoading = false
        #if DEBUG
        if isPreview { account = Self.previewAccount(tier: previewTier, interval: previewInterval) }
        #endif
    }
    func priceData(for tier: PlanTier, interval: BillingInterval) -> SubscriptionPrice? {
        guard tier == .pro else { return nil }
        return account?.plans.first(where: { $0.id == interval.rawValue })?.price
    }
    func price(for tier: PlanTier, interval: BillingInterval) -> String {
        tier == .free ? "Free" : priceData(for: tier, interval: interval).map { SubscriptionFormatting.money($0.amountMinor, currency: $0.currency) } ?? "Unavailable"
    }
    func monthlyPrice(for tier: PlanTier, interval: BillingInterval) -> String {
        guard tier != .free else { return "Free" }
        guard let price = priceData(for: tier, interval: interval) else { return "Unavailable" }
        let amount = interval == .annual ? Int((Double(price.amountMinor) / 12).rounded()) : price.amountMinor
        return SubscriptionFormatting.money(amount, currency: price.currency)
    }
    func summary(for tier: PlanTier) -> String {
        let id = tier == .free ? "free" : "monthly"
        return account?.plans.first(where: { $0.id == id })?.features.prefix(2).joined(separator: " · ") ?? "Plan details unavailable"
    }
    func isAvailable(tier: PlanTier, interval: BillingInterval) -> Bool { tier == .free || priceData(for: tier, interval: interval) != nil }
    func savings() -> Int? {
        guard let month = priceData(for: .pro, interval: .monthly), let year = priceData(for: .pro, interval: .annual), month.currency == year.currency else { return nil }
        return PlanCatalog.savings(monthly: Decimal(month.amountMinor), annual: Decimal(year.amountMinor))
    }
    func refresh() async {
        #if DEBUG
        if isPreview { return }
        #endif
        guard let owner = accountID, !isLoading else { return }
        let request = UUID(); revision = request; isLoading = true; error = nil
        defer { if revision == request { isLoading = false } }
        let value = await country()
        guard accountID == owner, revision == request, !Task.isCancelled else { return }
        eligibility = SubscriptionEligibility(countryCode: value)
        _ = await client.load(owner: owner)
        guard accountID == owner, revision == request, !Task.isCancelled else { return }
        account = client.account
        error = client.error.isEmpty ? nil : client.error
    }
    func beginPlan(_ tier: PlanTier, interval: BillingInterval) async -> URL? {
        #if DEBUG
        if isPreview { return nil }
        #endif
        guard let owner = accountID, !busy, account != nil else { return nil }
        let request = UUID(); operation = request; busy = true; error = nil; message = nil
        defer { if operation == request { busy = false } }
        do {
            let fresh = SubscriptionEligibility(countryCode: await country())
            guard accountID == owner, operation == request else { return nil }
            eligibility = fresh
            guard fresh.allowsStripeLinks, let account else { throw APIError.serverError("Subscription changes are unavailable for this storefront.") }
            if tier == .free {
                guard account.hasSubscription else { return nil }
                let url = try await client.portal(action: "cancel", owner: owner, eligibility: fresh)
                return accountID == owner && operation == request ? url : nil
            }
            if account.hasSubscription {
                if currentSubscription?.interval == interval { message = "This is your current billing interval."; return nil }
                let preview = try await client.preview(interval: interval.rawValue, owner: owner, eligibility: fresh)
                if accountID == owner && operation == request { changePreview = preview }
                return nil
            }
            let url = try await client.checkout(interval: interval.rawValue, owner: owner, eligibility: fresh)
            return accountID == owner && operation == request ? url : nil
        } catch {
            if accountID == owner, operation == request, !RequestCancellation.isCancellation(error) { self.error = error.localizedDescription }
            return nil
        }
    }
    func portalURL(action: String = "manage") async -> URL? {
        #if DEBUG
        if isPreview { return nil }
        #endif
        guard let owner = accountID, !busy else { return nil }
        let request = UUID(); operation = request; busy = true; error = nil
        defer { if operation == request { busy = false } }
        do {
            let fresh = SubscriptionEligibility(countryCode: await country())
            guard accountID == owner, operation == request else { return nil }
            eligibility = fresh
            let url = try await client.portal(action: action, owner: owner, eligibility: fresh)
            return accountID == owner && operation == request ? url : nil
        } catch {
            if accountID == owner, operation == request, !RequestCancellation.isCancellation(error) { self.error = error.localizedDescription }
            return nil
        }
    }
    func confirmChange(_ preview: SubscriptionIntervalPreview) async throws {
        guard let owner = accountID, changePreview == preview, !busy else { throw APIError.unauthorized }
        let request = UUID(); operation = request; busy = true
        defer { if operation == request { busy = false } }
        let fresh = SubscriptionEligibility(countryCode: await country())
        guard accountID == owner, operation == request else { throw CancellationError() }
        _ = try await client.confirm(preview, owner: owner, eligibility: fresh)
        guard accountID == owner, operation == request else { throw CancellationError() }
        changePreview = nil; message = "Your billing interval change is scheduled."
        await refresh()
    }
    func cancelScheduledChange() async {
        guard let owner = accountID, !busy else { return }
        let request = UUID(); operation = request; busy = true; error = nil
        defer { if operation == request { busy = false } }
        do {
            let fresh = SubscriptionEligibility(countryCode: await country())
            guard accountID == owner, operation == request else { return }
            _ = try await client.cancelIntervalChange(owner: owner, eligibility: fresh)
            guard accountID == owner, operation == request else { return }
            await refresh()
        } catch { if accountID == owner, operation == request { self.error = error.localizedDescription } }
    }
    private static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        let parser = ISO8601DateFormatter(); parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return parser.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
    #if DEBUG
    static func preview(tier: PlanTier = .pro, interval: BillingInterval = .monthly, cancellationScheduled: Bool = false, loading: Bool = false, error: String? = nil) -> SubscriptionStore {
        let store = SubscriptionStore(accountID: "preview")
        store.isPreview = true; store.previewTier = tier; store.previewInterval = interval
        store.account = loading || error != nil ? nil : previewAccount(tier: tier, interval: interval, cancellationScheduled: cancellationScheduled)
        store.isLoading = loading; store.error = error
        store.eligibility = SubscriptionEligibility(countryCode: "USA")
        return store
    }
    private static func previewAccount(tier: PlanTier, interval: BillingInterval, cancellationScheduled: Bool = false) -> SubscriptionAccount {
        // Preview fixtures only. Production pricing/features come from Stripe.
        let month = SubscriptionPrice(name: "Pro", amountMinor: 799, currency: "usd", billingInterval: "monthly")
        let year = SubscriptionPrice(name: "Pro", amountMinor: 7999, currency: "usd", billingInterval: "annual")
        let paid = tier == .pro
        let end = ISO8601DateFormatter().string(from: Calendar.current.date(byAdding: interval == .annual ? .year : .month, value: 1, to: Date())!)
        return SubscriptionAccount(billing: BillingStatusPayload(plan: paid ? "PRO" : "FREE", subscriptionStatus: paid ? "ACTIVE" : "NONE", billingInterval: paid ? interval.rawValue : nil, isPro: paid, cancelAtPeriodEnd: cancellationScheduled && paid, currentPeriodEnd: paid ? end : nil, remainingFreeOrders: paid ? nil : 6, active: paid),
            provider: paid ? "stripe" : "none", plans: [
                SubscriptionPlan(id: "free", name: "Free", price: nil, features: ["20 lifetime signing orders", "Invoice tools"]),
                SubscriptionPlan(id: "monthly", name: "Pro", price: month, features: ["Unlimited signing orders", "Tax reports"]),
                SubscriptionPlan(id: "annual", name: "Pro", price: year, features: ["Unlimited signing orders", "Tax reports"])],
            currentPrice: paid ? (interval == .annual ? year : month) : nil, currentPlanID: paid ? interval.rawValue : "free", hasSubscription: paid,
            trialEnd: nil, renewalDate: paid && !cancellationScheduled ? end : nil, cancellationDate: paid && cancellationScheduled ? end : nil, pendingUpdate: false, card: nil, billingDetails: nil,
            capabilities: SubscriptionCapabilities(manage: paid, paymentMethod: false, billingDetails: false, cancel: paid, resume: false, history: paid),
            paymentIssue: nil, history: SubscriptionHistory(items: [], nextCursor: nil))
    }
    #endif
}

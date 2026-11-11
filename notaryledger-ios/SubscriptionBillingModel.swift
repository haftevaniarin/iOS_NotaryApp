import Foundation
import Combine

@MainActor
final class SubscriptionBillingModel: ObservableObject {
    nonisolated deinit {}
    @Published private(set) var account: SubscriptionAccount?
    @Published private(set) var history = SubscriptionHistory(items: [], nextCursor: nil)
    @Published private(set) var isLoading = false
    @Published private(set) var isSyncing = false
    @Published private(set) var isLoadingHistory = false
    @Published private(set) var busy = false
    @Published private(set) var ownerID: String?
    @Published var error = ""
    private let api: APIService
    private let service: any BillingService
    private let defaults: UserDefaults
    private let subscriptionOnly: Bool
    private var revision = UUID()

    init(api: APIService? = nil, defaults: UserDefaults = .standard, subscriptionOnly: Bool = false, service: (any BillingService)? = nil) {
        self.api = api ?? .shared
        self.service = service ?? AccountBillingService(api: api)
        self.defaults = defaults
        self.subscriptionOnly = subscriptionOnly
    }
    var pendingCheckout: Bool {
        defaults.string(forKey: "notary_pending_checkout_owner") == ownerID
            && !(defaults.string(forKey: "notary_pending_checkout") ?? "").isEmpty
    }
    func load(owner: String) async -> BillingStatusPayload? {
        if ownerID != owner { account = nil; history = SubscriptionHistory(items: [], nextCursor: nil); ownerID = owner }
        let request = UUID(); revision = request
        isLoading = true; isSyncing = false; isLoadingHistory = false; error = ""
        defer { if revision == request { isLoading = false; isSyncing = false } }
        do {
            if pendingCheckout, let session = defaults.string(forKey: "notary_pending_checkout") {
                do { _ = try await service.syncCheckout(sessionID: session) }
                catch {
                    if RequestCancellation.isCancellation(error) { throw error }
                    guard ownerID == owner, revision == request else { return nil }
                    self.error = "The previous checkout could not be synchronized. Your subscription details are shown below. Refresh or continue checkout to try again."
                }
                try Task.checkCancellation()
                guard ownerID == owner, revision == request else { return nil }
            }
            for attempt in 0..<6 {
                let value = try await service.subscription(subscriptionOnly: subscriptionOnly)
                try Task.checkCancellation()
                guard ownerID == owner, revision == request else { return nil }
                account = value; history = value.history; isLoading = false
                if !value.pendingUpdate {
                    if value.hasSubscription || value.billing.hasProAccess {
                        if defaults.string(forKey: "notary_pending_checkout_owner") == owner {
                            defaults.removeObject(forKey: "notary_pending_checkout")
                            defaults.removeObject(forKey: "notary_pending_checkout_owner")
                        }
                    }
                    return value.billing
                }
                isSyncing = true
                if attempt < 5 { try await Task.sleep(for: .seconds(2)) }
            }
            return account?.billing
        } catch {
            guard ownerID == owner, revision == request, !Task.isCancelled, !RequestCancellation.isCancellation(error) else { return nil }
            if case APIError.httpError(404, _) = error {
                self.error = "Detailed subscription management is not available on this server yet. Your current access remains unchanged."
            } else { self.error = error.localizedDescription }
            return nil
        }
    }
    func loadMoreHistory(owner: String) async {
        guard ownerID == owner, !isLoadingHistory, let cursor = history.nextCursor else { return }
        let request = revision
        isLoadingHistory = true
        defer { if revision == request { isLoadingHistory = false } }
        do {
            let next = try await api.fetchSubscriptionHistory(cursor: cursor)
            try Task.checkCancellation()
            guard ownerID == owner, revision == request else { return }
            let existing = Set(history.items.map(\.id))
            history.items += next.items.filter { !existing.contains($0.id) }
            history.nextCursor = next.nextCursor
        } catch {
            if ownerID == owner, revision == request, !Task.isCancelled, !RequestCancellation.isCancellation(error) { self.error = error.localizedDescription }
        }
    }
    func checkout(interval: String, owner: String, eligibility: SubscriptionEligibility) async throws -> URL {
        guard ownerID == owner, let account, eligibility.allowsNewStripePurchase(hasStripeSubscription: account.hasSubscription),
              !account.billing.hasProAccess, account.plans.contains(where: { $0.id == interval && $0.price != nil }), !busy else {
            throw APIError.serverError("Subscription purchase is unavailable for this account or storefront.")
        }
        busy = true; error = ""
        defer { busy = false }
        let session = try await service.checkout(interval: interval)
        guard ownerID == owner, let sessionID = session.sessionId, let url = SubscriptionFormatting.trustedURL(session.url) else { throw APIError.invalidResponse }
        defaults.set(sessionID, forKey: "notary_pending_checkout")
        defaults.set(owner, forKey: "notary_pending_checkout_owner")
        return url
    }
    func portal(action: String, owner: String, eligibility: SubscriptionEligibility) async throws -> URL {
        guard ownerID == owner, eligibility.allowsStripeLinks, !busy else { throw APIError.serverError("Stripe management is unavailable in this storefront.") }
        busy = true; error = ""
        defer { busy = false }
        let session = try await service.portal(action: action)
        guard ownerID == owner, let url = SubscriptionFormatting.trustedURL(session.url) else { throw APIError.invalidResponse }
        return url
    }
    func preview(interval: String, owner: String, eligibility: SubscriptionEligibility) async throws -> SubscriptionIntervalPreview {
        guard ownerID == owner, eligibility.allowsStripeLinks, !busy else { throw APIError.serverError("Billing changes are unavailable in this storefront.") }
        busy = true; error = ""
        defer { busy = false }
        let preview = try await api.previewSubscriptionInterval(interval)
        guard ownerID == owner else { throw CancellationError() }
        return preview
    }
    func confirm(_ preview: SubscriptionIntervalPreview, owner: String, eligibility: SubscriptionEligibility) async throws -> BillingStatusPayload {
        guard ownerID == owner, eligibility.allowsStripeLinks, !busy else { throw APIError.serverError("Billing changes are unavailable in this storefront.") }
        busy = true; error = ""
        defer { busy = false }
        let result = try await api.confirmSubscriptionInterval(preview)
        guard ownerID == owner else { throw CancellationError() }
        return result
    }
    func cancelIntervalChange(owner: String, eligibility: SubscriptionEligibility) async throws -> BillingStatusPayload {
        guard ownerID == owner, eligibility.allowsStripeLinks, !busy else { throw APIError.serverError("Billing changes are unavailable in this storefront.") }
        busy = true; error = ""
        defer { busy = false }
        let result = try await api.changeBillingInterval(nil)
        guard ownerID == owner else { throw CancellationError() }
        return result
    }
}

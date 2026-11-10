import Foundation
import Observation

nonisolated struct BillingUsage: Decodable, Equatable {
    let signingsLogged: Int
    let invoicesSent: Int
    let signingLimit: Int?
    let remainingFreeOrders: Int?
    let hasExternalSubscription: Bool
}
nonisolated struct BillingUsageResponse: Decodable { let usage: BillingUsage }
nonisolated struct BillingInvoice: Identifiable, Equatable {
    let id: String
    let date: Date
    let price: String?
    let status: String
    var month: String { date.formatted(.dateTime.month(.wide).year()) }
}
nonisolated struct BillingSnapshot {
    let usage: BillingUsage?
    var invoices: [BillingInvoice]
    var notice: String?
    var nextCursor: String? = nil
}
nonisolated struct BillingInvoicePage { let items: [BillingInvoice]; let nextCursor: String? }

@MainActor protocol BillingService {
    func subscription(subscriptionOnly: Bool) async throws -> SubscriptionAccount
    func checkout(interval: String) async throws -> BillingSession
    func portal(action: String) async throws -> BillingSession
    func syncCheckout(sessionID: String) async throws -> BillingStatusPayload
    func snapshot(accountID: String, month: DateInterval) async throws -> BillingSnapshot
    func invoices(after cursor: String) async throws -> BillingInvoicePage
}
extension BillingService {
    func subscription(subscriptionOnly: Bool) async throws -> SubscriptionAccount { throw APIError.invalidResponse }
    func checkout(interval: String) async throws -> BillingSession { throw APIError.invalidResponse }
    func portal(action: String) async throws -> BillingSession { throw APIError.invalidResponse }
    func syncCheckout(sessionID: String) async throws -> BillingStatusPayload { throw APIError.invalidResponse }
    func invoices(after cursor: String) async throws -> BillingInvoicePage { BillingInvoicePage(items: [], nextCursor: nil) }
}

@MainActor struct AccountBillingService: BillingService {
    let api: APIService
    init(api: APIService? = nil) { self.api = api ?? .shared }
    func subscription(subscriptionOnly: Bool) async throws -> SubscriptionAccount { try await api.fetchSubscriptionAccount(subscriptionOnly: subscriptionOnly) }
    func checkout(interval: String) async throws -> BillingSession { try await api.createCheckoutSession(billingInterval: interval) }
    func portal(action: String) async throws -> BillingSession { try await api.createCustomerPortalSession(action: action) }
    func syncCheckout(sessionID: String) async throws -> BillingStatusPayload { try await api.syncCheckoutSession(sessionId: sessionID) }
    func snapshot(accountID: String, month: DateInterval) async throws -> BillingSnapshot {
        var usage: BillingUsage?, notice: String?
        do { usage = try await api.fetchBillingUsage(month: month) }
        catch {
            if RequestCancellation.isCancellation(error) { throw error }
            notice = "Monthly usage could not be loaded. Pull to refresh."
        }
        var invoices: [BillingInvoice] = []
        var nextCursor: String?
        do {
            let page = try await api.fetchSubscriptionHistory()
            invoices = Self.rows(page.items); nextCursor = page.nextCursor
        } catch {
            if RequestCancellation.isCancellation(error) { throw error }
            notice = [notice, "Subscription invoices could not be loaded. Pull to refresh."].compactMap { $0 }.joined(separator: " ")
        }
        return BillingSnapshot(usage: usage, invoices: invoices.sorted { $0.date > $1.date }, notice: notice, nextCursor: nextCursor)
    }
    func invoices(after cursor: String) async throws -> BillingInvoicePage {
        let page = try await api.fetchSubscriptionHistory(cursor: cursor)
        return BillingInvoicePage(items: Self.rows(page.items), nextCursor: page.nextCursor)
    }
    private static func rows(_ charges: [SubscriptionCharge]) -> [BillingInvoice] {
        charges.compactMap { charge in
            guard let date = DateParser.date(from: charge.date ?? "") else { return nil }
            return BillingInvoice(id: charge.id, date: date,
                price: SubscriptionFormatting.money(charge.amountMinor, currency: charge.currency),
                status: (charge.status ?? "Unknown").replacingOccurrences(of: "_", with: " ").capitalized)
        }
    }
}

@MainActor struct MockBillingService: BillingService {
    var signings = 14
    var sentInvoices = 3
    var tier: PlanTier = .pro
    var account: SubscriptionAccount?
    var failure: APIError?
    func subscription(subscriptionOnly: Bool) async throws -> SubscriptionAccount {
        if let failure { throw failure }
        guard let account else { throw APIError.invalidResponse }
        return account
    }
    func checkout(interval: String) async throws -> BillingSession {
        if let failure { throw failure }
        return BillingSession(url: "https://checkout.stripe.com/c/pay/mock", sessionId: "cs_mock")
    }
    func portal(action: String) async throws -> BillingSession {
        if let failure { throw failure }
        return BillingSession(url: "https://billing.stripe.com/p/session/mock", sessionId: "bps_mock")
    }
    func syncCheckout(sessionID: String) async throws -> BillingStatusPayload { try await subscription(subscriptionOnly: true).billing }
    func snapshot(accountID: String, month: DateInterval) async throws -> BillingSnapshot {
        var invoices: [BillingInvoice] = []
        // Preview fixtures only; account invoices are loaded from Stripe above.
        invoices = [0, -1].map { offset in
            BillingInvoice(id: "preview-\(offset)", date: Calendar.current.date(byAdding: .month, value: offset, to: Date())!,
                price: SubscriptionFormatting.money(799, currency: "usd"), status: "Paid")
        }
        return BillingSnapshot(usage: BillingUsage(signingsLogged: signings, invoicesSent: sentInvoices, signingLimit: tier == .free ? 20 : nil,
            remainingFreeOrders: tier == .free ? 6 : nil, hasExternalSubscription: false), invoices: invoices)
    }
}

@MainActor @Observable final class BillingOverviewModel {
    nonisolated deinit {}
    private(set) var snapshot: BillingSnapshot?
    private(set) var isLoading = false
    private(set) var isLoadingInvoices = false
    private(set) var ownerID: String?
    private let service: any BillingService
    private var revision = UUID()
    init(service: any BillingService) { self.service = service }
    func loadMoreInvoices(accountID: String?) async {
        guard let accountID, ownerID == accountID, !isLoadingInvoices, let cursor = snapshot?.nextCursor else { return }
        let request = revision; isLoadingInvoices = true
        defer { if revision == request { isLoadingInvoices = false } }
        do {
            let page = try await service.invoices(after: cursor)
            guard !Task.isCancelled, ownerID == accountID, revision == request else { return }
            let known = Set(snapshot?.invoices.map(\.id) ?? [])
            snapshot?.invoices += page.items.filter { !known.contains($0.id) }
            snapshot?.nextCursor = page.nextCursor
        } catch {
            if ownerID == accountID, revision == request, !RequestCancellation.isCancellation(error) { snapshot?.notice = "More invoices could not be loaded. Please try again." }
        }
    }
    func load(accountID: String) async {
        if ownerID != accountID { snapshot = nil; ownerID = accountID }
        let request = UUID(); revision = request; isLoading = true; isLoadingInvoices = false
        defer { if revision == request { isLoading = false } }
        do {
            let month = Calendar.current.dateInterval(of: .month, for: Date())!
            let value = try await service.snapshot(accountID: accountID, month: month)
            guard !Task.isCancelled, revision == request, ownerID == accountID else { return }
            snapshot = value
        } catch {
            guard !Task.isCancelled, revision == request, !RequestCancellation.isCancellation(error) else { return }
            snapshot = BillingSnapshot(usage: snapshot?.usage, invoices: snapshot?.invoices ?? [], notice: "Billing information is unavailable. Please try again.")
        }
    }
}


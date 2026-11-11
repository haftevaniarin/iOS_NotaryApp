import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    enum Route {
        case auth
        case app
        case maintenance(MaintenanceStatus)
    }

    @Published var route: Route = SessionStorage.getAccessToken() == nil ? .auth : .app
    @Published var currentUser: AuthUser? = SessionStorage.getCurrentUser() {
        didSet { if oldValue?.id != currentUser?.id { clearBillingStatus(); subscriptions.bind(accountID: currentUser?.id) } }
    }
    let subscriptions: SubscriptionStore
    @Published var orders: [SigningOrder] = []
    @Published var expenses: [Expense] = []
    @Published var isLoading = false
    @Published var errorMessage = ""
    private var refreshRequestID: UUID?
    @Published private(set) var billingStatus: BillingStatusPayload?
    @Published private(set) var billingLoadFailed = false
    @Published private(set) var billingReturnRevision = 0
    private var billingRequestID: UUID?
    private var billingRequestOwner: String?

    let auth: AuthFlowModel
    @Published var selectedSection: AppSection = .dashboard
    @Published private(set) var isRestoringSession = true
    private var intendedSection: AppSection?
    private var hasIncomingAuthLink = false
    private let api: APIService

    // SwiftUI can release this outside a Swift task. No actor-bound cleanup is
    // needed; avoid the isolated-deinit crash on older iOS concurrency runtimes.
    // https://github.com/swiftlang/swift/issues/88036
    nonisolated deinit {}

    init(api: APIService? = nil) {
        #if DEBUG
        subscriptions = ProcessInfo.processInfo.arguments.contains("--stripe-billing-ui-fixtures") ? .preview(tier: .free) : SubscriptionStore()
        #else
        subscriptions = SubscriptionStore()
        #endif
        self.api = api ?? APIService.shared
        self.auth = AuthFlowModel(api: self.api)
        self.api.onAuthenticationRequired = { [weak self] in self?.requireAuthentication() }
        subscriptions.bind(accountID: currentUser?.id)
    }

    func boot() async {
        defer { isRestoringSession = false }
        guard !hasIncomingAuthLink else { return }
        let maintenance = await api.fetchMaintenanceStatus()
        guard !hasIncomingAuthLink else { return }
        if maintenance.enabled {
            route = .maintenance(maintenance)
            return
        }
        do {
            let restored = try await api.restoreSession()
            guard !hasIncomingAuthLink else { return }
            currentUser = restored
            selectedSection = allowedDestination(intendedSection ?? selectedSection)
            intendedSection = nil
            route = .app
            await refreshAll()
        } catch APIError.unauthorized {
            if !hasIncomingAuthLink { signOutLocally(preserveDestination: intendedSection != nil) }
        } catch {
            guard !hasIncomingAuthLink else { return }
            errorMessage = error.localizedDescription
            route = currentUser == nil ? .auth : .app
        }
    }

    func didAuthenticate(_ response: AuthResponse) async {
        SessionStorage.saveSession(response)
        if let user = response.user {
            currentUser = user
        } else {
            currentUser = try? await api.fetchCurrentUser()
        }
        selectedSection = allowedDestination(intendedSection ?? .dashboard)
        intendedSection = nil
        hasIncomingAuthLink = false
        route = .app
        await refreshAll()
    }

    func openURL(_ url: URL) {
        if let billingReturn = BillingReturnLink(url: url) {
            // Return links only trigger navigation and a server refresh; they never grant access.
            if billingReturn.outcome == .checkoutCancelled,
               let owner = currentUser?.id,
               UserDefaults.standard.string(forKey: "notary_pending_checkout_owner") == owner {
                UserDefaults.standard.removeObject(forKey: "notary_pending_checkout")
                UserDefaults.standard.removeObject(forKey: "notary_pending_checkout_owner")
            }
            billingReturnRevision += 1
            openURL(URL(string: "notaryledger://billing")!)
            return
        }
        guard let link = AuthLink(url: url) else { return }
        if link.screen == .login || link.screen == .signup { intendedSection = link.destination }
        else if let destination = link.destination { intendedSection = destination }
        if let screen = link.screen {
            if (screen == .login || screen == .signup), !isRestoringSession,
               currentUser != nil, SessionStorage.getAccessToken() != nil {
                selectedSection = allowedDestination(intendedSection ?? .dashboard)
                intendedSection = nil
                route = .app
                return
            }
            isRestoringSession = false
            hasIncomingAuthLink = true
            auth.navigate(screen, token: link.token)
            route = .auth
        } else if let destination = link.destination {
            // Preserve a protected link while the saved session is checked.
            guard !isRestoringSession else { return }
            if currentUser != nil, SessionStorage.getAccessToken() != nil {
                selectedSection = allowedDestination(destination)
                intendedSection = nil
                route = .app
            } else {
                hasIncomingAuthLink = true
                auth.navigate(.login)
                route = .auth
            }
        }
    }

    private func allowedDestination(_ section: AppSection) -> AppSection {
        section == .adminAudit && currentUser?.canAccessAdminAudit != true ? .dashboard : section
    }

    private func requireAuthentication() {
        guard case .app = route else { return }
        signOutLocally(preserveDestination: true)
        errorMessage = "Your session has expired. Please sign in again."
        auth.showError(errorMessage)
    }

    func signOut() async {
        await api.logout()
        signOutLocally()
    }

    func signOutLocally(preserveDestination: Bool = false) {
        if preserveDestination { intendedSection = intendedSection ?? selectedSection }
        else { intendedSection = nil }
        selectedSection = .dashboard
        hasIncomingAuthLink = false
        auth.reset()
        SessionStorage.clearSession()
        currentUser = nil
        orders = []
        expenses = []
        route = .auth
    }

    func refreshAll() async {
        guard !Task.isCancelled else { return }
        let requestID = UUID()
        let owner = currentUser?.id
        refreshRequestID = requestID
        isLoading = true
        errorMessage = ""
        defer {
            if refreshRequestID == requestID {
                isLoading = false
                refreshRequestID = nil
            }
        }

        do {
            let refreshedOrders = try await api.fetchOrders()
            try Task.checkCancellation()
            guard refreshRequestID == requestID, currentUser?.id == owner else { return }
            let refreshedExpenses = try await api.fetchExpenses()
            try Task.checkCancellation()
            guard refreshRequestID == requestID, currentUser?.id == owner else { return }
            orders = refreshedOrders
            expenses = refreshedExpenses
        } catch {
            guard !Task.isCancelled, !RequestCancellation.isCancellation(error),
                  refreshRequestID == requestID, currentUser?.id == owner else { return }
            switch error {
            case APIError.maintenance(let status): route = .maintenance(status)
            case APIError.unauthorized: requireAuthentication()
            default: errorMessage = error.localizedDescription
            }
        }
        guard !Task.isCancelled, refreshRequestID == requestID, currentUser?.id == owner else { return }
        await refreshBillingStatus()
    }

    func refreshBillingStatus() async {
        guard !Task.isCancelled, let owner = currentUser?.id, billingRequestOwner != owner else { return }
        let requestID = UUID()
        billingRequestID = requestID
        billingRequestOwner = owner
        defer {
            if billingRequestID == requestID { billingRequestID = nil; billingRequestOwner = nil }
        }
        do {
            let status = try await api.fetchBillingStatus()
            try Task.checkCancellation()
            guard currentUser?.id == owner, billingRequestID == requestID else { return }
            updateBillingStatus(status, for: owner)
        } catch {
            guard !Task.isCancelled, !RequestCancellation.isCancellation(error),
                  currentUser?.id == owner, billingRequestID == requestID else { return }
            billingLoadFailed = billingStatus == nil
        }
    }

    func updateBillingStatus(_ status: BillingStatusPayload, for owner: String) {
        guard currentUser?.id == owner else { return }
        billingStatus = status
        billingLoadFailed = false
        billingRequestID = nil
        billingRequestOwner = nil
    }

    private func clearBillingStatus() {
        billingStatus = nil
        billingLoadFailed = false
        billingRequestID = nil
        billingRequestOwner = nil
    }

    func upsertOrder(_ order: SigningOrder) {
        if let index = orders.firstIndex(where: { $0.id == order.id }) {
            orders[index] = order
        } else {
            orders.insert(order, at: 0)
        }
        orders.sort { $0.date > $1.date }
    }

    func removeOrder(id: String) {
        orders.removeAll { $0.id == id }
    }

    func upsertExpense(_ expense: Expense) {
        if let index = expenses.firstIndex(where: { $0.id == expense.id }) {
            expenses[index] = expense
        } else {
            expenses.insert(expense, at: 0)
        }
        expenses.sort { $0.date > $1.date }
    }

    func removeExpense(id: String) {
        expenses.removeAll { $0.id == id }
    }
}

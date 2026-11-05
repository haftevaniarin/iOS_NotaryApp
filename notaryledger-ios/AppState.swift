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
    @Published var currentUser: AuthUser? = SessionStorage.getCurrentUser()
    @Published var orders: [SigningOrder] = []
    @Published var expenses: [Expense] = []
    @Published var isLoading = false
    @Published var errorMessage = ""

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
        self.api = api ?? APIService.shared
        self.auth = AuthFlowModel(api: self.api)
        self.api.onAuthenticationRequired = { [weak self] in self?.requireAuthentication() }
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
        isLoading = true
        errorMessage = ""
        defer { isLoading = false }

        do {
            orders = try await api.fetchOrders()
            expenses = try await api.fetchExpenses()
        } catch APIError.maintenance(let status) {
            route = .maintenance(status)
        } catch APIError.unauthorized {
            requireAuthentication()
        } catch {
            errorMessage = error.localizedDescription
        }
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

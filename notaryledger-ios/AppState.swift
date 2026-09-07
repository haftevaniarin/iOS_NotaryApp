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

    private let api: APIService

    init(api: APIService? = nil) {
        self.api = api ?? APIService.shared
    }

    func boot() async {
        let maintenance = await api.fetchMaintenanceStatus()
        if maintenance.enabled {
            route = .maintenance(maintenance)
            return
        }
        route = SessionStorage.getAccessToken() == nil ? .auth : .app
        if case .app = route {
            await refreshAll()
        }
    }

    func didAuthenticate(_ response: AuthResponse) async {
        SessionStorage.saveSession(response)
        currentUser = response.user
        route = .app
        await refreshAll()
    }

    func signOut() {
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
            signOut()
            errorMessage = "Please sign in again."
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

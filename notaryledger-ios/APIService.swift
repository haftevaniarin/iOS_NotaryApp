import Foundation

enum APIError: Error, LocalizedError, Equatable {
    case invalidURL
    case invalidResponse
    case unauthorized
    case maintenance(MaintenanceStatus)
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The app could not build a valid server request."
        case .invalidResponse:
            return "The server returned an unexpected response."
        case .unauthorized:
            return "Please sign in again."
        case .maintenance(let status):
            return status.message ?? "Notary Ledger is temporarily unavailable for maintenance."
        case .serverError(let message):
            return message
        }
    }
}

struct EmptyResponse: Decodable {}

final class APIService {
    static let shared = APIService()

    private let baseURL: String
    private let session: URLSession
    private var lastMaintenanceCheck: Date?
    private var cachedMaintenance = MaintenanceStatus.disabled
    private let maintenanceTTL: TimeInterval = 60

    init(baseURL: String = APIConfig.baseURL, session: URLSession = .shared) {
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.session = session
    }

    func makeRequest(
        path: String,
        method: String,
        token: String? = nil,
        body: Data? = nil,
        queryItems: [URLQueryItem] = []
    ) throws -> URLRequest {
        guard var components = URLComponents(string: baseURL + path) else {
            throw APIError.invalidURL
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(baseURL, forHTTPHeaderField: "Origin")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = body
        return request
    }

    func encodedBody<T: Encodable>(_ payload: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(payload)
    }

    func signup(fullName: String, email: String, password: String) async throws -> AuthResponse {
        let payload = SignupRequest(fullName: fullName, email: email, password: password)
        let request = try makeRequest(path: "/api/auth/signup", method: "POST", body: encodedBody(payload))
        let response = try await perform(request, decodeTo: AuthResponse.self)
        SessionStorage.saveSession(response)
        return response
    }

    func login(email: String, password: String) async throws -> AuthResponse {
        let payload = LoginRequest(email: email, password: password)
        let request = try makeRequest(path: "/api/auth/login", method: "POST", body: encodedBody(payload))
        let response = try await perform(request, decodeTo: AuthResponse.self)
        SessionStorage.saveSession(response)
        return response
    }

    func forgotPassword(email: String) async throws {
        let body = try encodedBody(["email": email])
        let request = try makeRequest(path: "/api/auth/forgot-password", method: "POST", body: body)
        _ = try await perform(request, decodeTo: EmptyResponse.self)
    }

    func resetPassword(token: String, password: String) async throws {
        let body = try encodedBody(["token": token, "password": password])
        let request = try makeRequest(path: "/api/auth/reset-password", method: "POST", body: body)
        _ = try await perform(request, decodeTo: EmptyResponse.self)
    }

    func verifyEmail(token: String) async throws {
        let body = try encodedBody(["token": token])
        let request = try makeRequest(path: "/api/auth/verify-email", method: "POST", body: body)
        _ = try await perform(request, decodeTo: EmptyResponse.self)
    }

    func fetchMaintenanceStatus() async -> MaintenanceStatus {
        do {
            let request = try makeRequest(path: APIConfig.maintenancePath, method: "GET")
            return try await perform(request, decodeTo: MaintenanceStatus.self, allowNotFoundAsEmptyMaintenance: true)
        } catch {
            return .disabled
        }
    }

    func fetchOrders() async throws -> [SigningOrder] {
        let request = try await authenticatedRequest(path: "/api/orders", method: "GET")
        var orders = try await performAuthenticated(request, decodeTo: [SigningOrder].self)
        orders.sort { $0.date > $1.date }
        return orders
    }

    func createOrder(_ order: SigningOrderPayload) async throws -> SigningOrder {
        let request = try await authenticatedRequest(path: "/api/orders", method: "POST", body: encodedBody(order))
        return try await performAuthenticated(request, decodeTo: SigningOrder.self)
    }

    func updateOrder(orderId: String, order: SigningOrderPayload) async throws -> SigningOrder {
        let request = try await authenticatedRequest(path: "/api/orders/\(orderId)", method: "PUT", body: encodedBody(order))
        return try await performAuthenticated(request, decodeTo: SigningOrder.self)
    }

    func deleteOrder(orderId: String) async throws {
        let request = try await authenticatedRequest(path: "/api/orders/\(orderId)", method: "DELETE")
        _ = try await performAuthenticated(request, decodeTo: EmptyResponse.self)
    }

    func fetchExpenses() async throws -> [Expense] {
        let request = try await authenticatedRequest(path: "/api/expenses", method: "GET")
        var expenses = try await performAuthenticated(request, decodeTo: [Expense].self)
        expenses.sort { $0.date > $1.date }
        return expenses
    }

    func createExpense(_ expense: ExpensePayload) async throws -> Expense {
        let request = try await authenticatedRequest(path: "/api/expenses", method: "POST", body: encodedBody(expense))
        return try await performAuthenticated(request, decodeTo: Expense.self)
    }

    func updateExpense(expenseId: String, expense: ExpensePayload) async throws -> Expense {
        let request = try await authenticatedRequest(path: "/api/expenses/\(expenseId)", method: "PUT", body: encodedBody(expense))
        return try await performAuthenticated(request, decodeTo: Expense.self)
    }

    func deleteExpense(expenseId: String) async throws {
        let request = try await authenticatedRequest(path: "/api/expenses/\(expenseId)", method: "DELETE")
        _ = try await performAuthenticated(request, decodeTo: EmptyResponse.self)
    }

    func fetchTaxSummary(taxYear: Int) async throws -> TaxSummary {
        let request = try await authenticatedRequest(
            path: "/api/reports/tax-summary",
            method: "GET",
            queryItems: [URLQueryItem(name: "taxYear", value: String(taxYear))]
        )
        return try await performAuthenticated(request, decodeTo: TaxSummary.self)
    }

    func requestInvoice(_ invoiceRequest: InvoiceRequest) async throws -> Invoice {
        let request = try await authenticatedRequest(path: "/api/invoices", method: "POST", body: encodedBody(invoiceRequest))
        return try await performAuthenticated(request, decodeTo: Invoice.self)
    }

    func updateProfile(firstName: String, lastName: String) async throws -> AuthUser {
        let fullName = [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ")
        let body = try encodedBody(["firstName": firstName, "lastName": lastName, "fullName": fullName])
        let request = try await authenticatedRequest(path: "/api/profile", method: "PUT", body: body)
        let user = try await performAuthenticated(request, decodeTo: AuthUser.self)
        SessionStorage.saveCurrentUser(user)
        return user
    }

    func changePassword(currentPassword: String, newPassword: String) async throws {
        let body = try encodedBody(["currentPassword": currentPassword, "newPassword": newPassword])
        let request = try await authenticatedRequest(path: "/api/profile/password", method: "PUT", body: body)
        _ = try await performAuthenticated(request, decodeTo: EmptyResponse.self)
    }

    func requestDataExport() async throws {
        let request = try await authenticatedRequest(path: "/api/account/export", method: "POST")
        _ = try await performAuthenticated(request, decodeTo: EmptyResponse.self)
    }

    func deleteAccount() async throws {
        let request = try await authenticatedRequest(path: "/api/account", method: "DELETE")
        _ = try await performAuthenticated(request, decodeTo: EmptyResponse.self)
        SessionStorage.clearSession()
    }

    func contactSupport(_ payload: SupportContactRequest) async throws {
        let request = try await authenticatedRequest(path: "/api/support/contact", method: "POST", body: encodedBody(payload))
        _ = try await performAuthenticated(request, decodeTo: EmptyResponse.self)
    }

    private func authenticatedRequest(
        path: String,
        method: String,
        body: Data? = nil,
        queryItems: [URLQueryItem] = []
    ) async throws -> URLRequest {
        try await ensureMaintenanceAllowsRequests()
        guard let token = SessionStorage.getAccessToken() else {
            throw APIError.unauthorized
        }
        return try makeRequest(path: path, method: method, token: token, body: body, queryItems: queryItems)
    }

    private func ensureMaintenanceAllowsRequests() async throws {
        let shouldCheck = lastMaintenanceCheck.map { Date().timeIntervalSince($0) > maintenanceTTL } ?? true
        if shouldCheck {
            cachedMaintenance = await fetchMaintenanceStatus()
            lastMaintenanceCheck = Date()
        }
        if cachedMaintenance.enabled {
            throw APIError.maintenance(cachedMaintenance)
        }
    }

    private func performAuthenticated<T: Decodable>(_ request: URLRequest, decodeTo type: T.Type) async throws -> T {
        do {
            return try await perform(request, decodeTo: type)
        } catch APIError.unauthorized {
            guard try await refreshSession() else {
                throw APIError.unauthorized
            }
            var retry = request
            if let token = SessionStorage.getAccessToken() {
                retry.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            return try await perform(retry, decodeTo: type)
        }
    }

    private func refreshSession() async throws -> Bool {
        guard let refreshToken = SessionStorage.getRefreshToken() else {
            return false
        }
        let body = try encodedBody(["refreshToken": refreshToken])
        let request = try makeRequest(path: "/api/auth/refresh", method: "POST", body: body)
        do {
            let response = try await perform(request, decodeTo: AuthResponse.self)
            SessionStorage.saveSession(response)
            return true
        } catch {
            SessionStorage.clearSession()
            return false
        }
    }

    private func perform<T: Decodable>(
        _ request: URLRequest,
        decodeTo type: T.Type,
        allowNotFoundAsEmptyMaintenance: Bool = false
    ) async throws -> T {
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if allowNotFoundAsEmptyMaintenance, httpResponse.statusCode == 404, let disabled = MaintenanceStatus.disabled as? T {
            return disabled
        }
        if httpResponse.statusCode == 401 {
            throw APIError.unauthorized
        }
        if !(200...299).contains(httpResponse.statusCode) {
            throw APIError.serverError(Self.normalizedErrorMessage(from: data))
        }
        if T.self == EmptyResponse.self {
            return EmptyResponse() as! T
        }
        if data.isEmpty {
            throw APIError.invalidResponse
        }
        return try decodeEnvelopeOrDirect(type, from: data)
    }

    private func decodeEnvelopeOrDirect<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        if let direct = try? decoder.decode(T.self, from: data) {
            return direct
        }
        if let envelope = try? decoder.decode(ResponseEnvelope<T>.self, from: data) {
            return envelope.value
        }
        return try decoder.decode(T.self, from: data)
    }

    static func normalizedErrorMessage(from data: Data) -> String {
        guard !data.isEmpty else {
            return "The server could not complete the request."
        }
        if let apiError = try? JSONDecoder().decode(BackendError.self, from: data) {
            return apiError.displayMessage
        }
        return String(data: data, encoding: .utf8) ?? "The server could not complete the request."
    }
}

private struct BackendError: Decodable {
    let message: String?
    let error: String?
    let errors: [String]?
    let fieldErrors: [String: [String]]?

    var displayMessage: String {
        if let message, !message.isEmpty { return message }
        if let error, !error.isEmpty { return error }
        if let errors, !errors.isEmpty { return errors.joined(separator: "\n") }
        if let fieldErrors, !fieldErrors.isEmpty {
            return fieldErrors
                .sorted { $0.key < $1.key }
                .flatMap { key, values in values.map { "\(key): \($0)" } }
                .joined(separator: "\n")
        }
        return "The server could not complete the request."
    }
}

private struct ResponseEnvelope<T: Decodable>: Decodable {
    let value: T

    enum CodingKeys: String, CodingKey {
        case data
        case items
        case orders
        case expenses
        case invoice
        case user
        case summary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try container.decodeIfPresent(T.self, forKey: .data) {
            self.value = value
        } else if let value = try container.decodeIfPresent(T.self, forKey: .items) {
            self.value = value
        } else if let value = try container.decodeIfPresent(T.self, forKey: .orders) {
            self.value = value
        } else if let value = try container.decodeIfPresent(T.self, forKey: .expenses) {
            self.value = value
        } else if let value = try container.decodeIfPresent(T.self, forKey: .invoice) {
            self.value = value
        } else if let value = try container.decodeIfPresent(T.self, forKey: .user) {
            self.value = value
        } else {
            value = try container.decode(T.self, forKey: .summary)
        }
    }
}

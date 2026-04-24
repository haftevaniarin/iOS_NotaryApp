import Foundation

enum APIError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL."
        case .invalidResponse:
            return "Invalid server response."
        case .unauthorized:
            return "Unauthorized."
        case .serverError(let message):
            return message
        }
    }
}

final class APIService {
    static let shared = APIService()
    private init() {}

    private func makeRequest(
        path: String,
        method: String,
        token: String? = nil,
        body: Data? = nil
    ) throws -> URLRequest {
        guard let url = URL(string: APIConfig.baseURL + path) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = body
        return request
    }

    private func perform<T: Decodable>(_ request: URLRequest, decodeTo type: T.Type) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw APIError.unauthorized
        }

        if !(200...299).contains(httpResponse.statusCode) {
            let message = String(data: data, encoding: .utf8) ?? "Server error."
            throw APIError.serverError(message)
        }

        return try JSONDecoder().decode(T.self, from: data)
    }

    func signup(fullName: String, email: String, password: String) async throws -> AuthResponse {
        let payload = SignupRequest(fullName: fullName, email: email, password: password)
        let body = try JSONEncoder().encode(payload)
    let request = try makeRequest(path: "/auth/signup", method: "POST", token: SessionStorage.getToken(), body: body)
        let response = try await perform(request, decodeTo: AuthResponse.self)
        SessionStorage.saveToken(response.token)
        SessionStorage.saveCurrentUser(response.user)
        return response
    }

    func login(email: String, password: String) async throws -> AuthResponse {
        let payload = LoginRequest(email: email, password: password)
        let body = try JSONEncoder().encode(payload)
    let request = try makeRequest(path: "/auth/login", method: "POST", token: SessionStorage.getToken(), body: body)
        let response = try await perform(request, decodeTo: AuthResponse.self)
        SessionStorage.saveToken(response.token)
        SessionStorage.saveCurrentUser(response.user)
        return response
    }

    func fetchOrders(token: String) async throws -> [SigningOrder] {
        let request = try makeRequest(path: "/orders", method: "GET", token: token)
        var orders = try await perform(request, decodeTo: [SigningOrder].self)
        // normalize/sort by date descending
        orders.sort { a, b in
            let fa = a.date
            let fb = b.date
            return fa > fb
        }
        return orders
    }

    func createOrder(token: String, order: SigningOrderRequest) async throws -> SigningOrder {
        let body = try JSONEncoder().encode(order)
        let request = try makeRequest(path: "/orders", method: "POST", token: token, body: body)
        return try await perform(request, decodeTo: SigningOrder.self)
    }

    func updateOrder(token: String, orderId: String, order: SigningOrderRequest) async throws -> SigningOrder {
        let body = try JSONEncoder().encode(order)
        let request = try makeRequest(path: "/orders/\(orderId)", method: "PUT", token: token, body: body)
        return try await perform(request, decodeTo: SigningOrder.self)
    }

    func deleteOrder(token: String, orderId: String) async throws {
        let request = try makeRequest(path: "/orders/\(orderId)", method: "DELETE", token: token)
        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw APIError.unauthorized
        }

        if !(200...299).contains(httpResponse.statusCode) {
            throw APIError.serverError("Failed to delete order.")
        }
    }
}

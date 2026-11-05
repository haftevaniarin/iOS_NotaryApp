import Foundation

nonisolated enum APIError: Error, LocalizedError, Equatable {
    case invalidURL
    case invalidResponse
    case unauthorized
    case maintenance(MaintenanceStatus)
    case serverError(String)
    case httpError(Int, String)

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
        case .serverError(let message), .httpError(_, let message):
            return message
        }
    }
}

struct EmptyResponse: Decodable {}

final class APIService {
    #if DEBUG
    // Allows UI snapshots to use an isolated fixture service without calling staging.
    static var shared = APIService()
    #else
    static let shared = APIService()
    #endif

    private let baseURL: String
    private let session: URLSession
    private var lastMaintenanceCheck: Date?
    private var cachedMaintenance = MaintenanceStatus.disabled
    private let maintenanceTTL: TimeInterval = 60
    private var refreshTask: Task<Bool, Error>?

    init(baseURL: String = APIConfig.baseURL, session: URLSession? = nil) {
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.session = session ?? URLSession(configuration: Self.defaultSessionConfiguration())
    }

    static func defaultSessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpCookieStorage = nil
        return configuration
    }

    func makeRequest(
        path: String,
        method: String,
        token: String? = nil,
        body: Data? = nil,
        queryItems: [URLQueryItem] = []
    ) throws -> URLRequest {
        let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        guard var components = URLComponents(string: baseURL + normalizedPath) else {
            throw APIError.invalidURL
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpShouldHandleCookies = false
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = body
        return request
    }

    func makeMultipartRequest(
        path: String,
        method: String = "POST",
        token: String? = nil,
        formFields: [String: String] = [:],
        files: [MultipartFile]
    ) throws -> URLRequest {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()

        for (name, value) in formFields {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            body.append("\(value)\r\n")
        }

        for file in files {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"\(file.fieldName)\"; filename=\"\(file.fileName)\"\r\n")
            body.append("Content-Type: \(file.mimeType)\r\n\r\n")
            body.append(file.data)
            body.append("\r\n")
        }

        body.append("--\(boundary)--\r\n")

        var request = try makeRequest(path: path, method: method, token: token, body: body)
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        return request
    }

    func encodedBody<T: Encodable>(_ payload: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(payload)
    }

    func encodedMutableBody<T: Encodable>(_ payload: T) throws -> Data {
        let data = try encodedBody(payload)
        let object = try JSONSerialization.jsonObject(with: data)
        let sanitized = Self.sanitizedMutablePayload(object)
        return try JSONSerialization.data(withJSONObject: sanitized, options: [.sortedKeys])
    }

    func register(firstName: String, lastName: String, email: String, password: String) async throws -> RegistrationResult {
        clearCookiesForPublicAuth()
        let payload = SignupRequest(firstName: firstName, lastName: lastName, email: email, password: password)
        var request = try makeRequest(path: "/api/auth/register", method: "POST", body: encodedMutableBody(payload))
        request.timeoutInterval = 90
        let response = try await perform(request, decodeTo: RegistrationResponse.self)
        guard let result = response.result else {
            throw APIError.invalidResponse
        }
        if case .authenticated(let authResponse) = result {
            SessionStorage.saveSession(authResponse)
        }
        return result
    }

    func signup(fullName: String, email: String, password: String) async throws -> RegistrationResult {
        let parts = fullName.split(separator: " ", maxSplits: 1).map(String.init)
        return try await register(
            firstName: parts.first ?? "",
            lastName: parts.dropFirst().first ?? "",
            email: email,
            password: password
        )
    }

    func login(email: String, password: String) async throws -> AuthResponse {
        clearCookiesForPublicAuth()
        let payload = LoginRequest(email: email, password: password)
        let request = try makeRequest(path: "/api/auth/login", method: "POST", body: encodedBody(payload))
        let response = try await perform(request, decodeTo: AuthResponse.self)
        guard response.refreshToken != nil else { throw APIError.invalidResponse }
        SessionStorage.saveSession(response)
        return response
    }

    func restoreSession() async throws -> AuthUser {
        guard try await refreshSession() else {
            throw APIError.unauthorized
        }
        return try await fetchCurrentUser()
    }

    func forgotPassword(email: String) async throws {
        clearCookiesForPublicAuth()
        let body = try encodedBody(["email": email])
        let request = try makeRequest(path: "/api/auth/forgot-password", method: "POST", body: body)
        _ = try await perform(request, decodeTo: EmptyResponse.self)
    }

    func resetPassword(token: String, password: String) async throws {
        clearCookiesForPublicAuth()
        let body = try encodedBody(["token": token, "password": password])
        let request = try makeRequest(path: "/api/auth/reset-password", method: "POST", body: body)
        _ = try await perform(request, decodeTo: EmptyResponse.self)
    }

    func verifyEmail(token: String) async throws {
        clearCookiesForPublicAuth()
        let body = try encodedBody(["token": token])
        let request = try makeRequest(path: "/api/auth/verify-email", method: "POST", body: body)
        _ = try await perform(request, decodeTo: EmptyResponse.self)
    }

    func resendVerification(email: String) async throws {
        clearCookiesForPublicAuth()
        let body = try encodedBody(["email": email])
        let request = try makeRequest(path: "/api/auth/resend-verification", method: "POST", body: body)
        _ = try await perform(request, decodeTo: EmptyResponse.self)
    }

    func fetchCurrentUser() async throws -> AuthUser {
        let request = try await authenticatedRequest(path: "/api/auth/me", method: "GET")
        let user = try await performAuthenticated(request, decodeTo: AuthUser.self)
        SessionStorage.saveCurrentUser(user)
        return user
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
        let request = try await authenticatedRequest(path: "/api/orders", method: "POST", body: encodedMutableBody(order))
        return try await performAuthenticated(request, decodeTo: SigningOrder.self)
    }

    func updateOrder(orderId: String, order: SigningOrderPayload) async throws -> SigningOrder {
        let request = try await authenticatedRequest(path: "/api/orders/\(orderId)", method: "PUT", body: encodedMutableBody(order))
        return try await performAuthenticated(request, decodeTo: SigningOrder.self)
    }

    func updateOrderMileage(orderId: String, mileage: Double?, travelFee: Double?) async throws -> SigningOrder {
        let payload = MileagePayload(mileage: mileage, travelFee: travelFee)
        let request = try await authenticatedRequest(path: "/api/orders/\(orderId)/mileage", method: "PATCH", body: encodedMutableBody(payload))
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
        let request = try await authenticatedRequest(path: "/api/expenses", method: "POST", body: encodedMutableBody(expense))
        return try await performAuthenticated(request, decodeTo: Expense.self)
    }

    func updateExpense(expenseId: String, expense: ExpensePayload) async throws -> Expense {
        let request = try await authenticatedRequest(path: "/api/expenses/\(expenseId)", method: "PUT", body: encodedMutableBody(expense))
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
        let report = try await performAuthenticated(request, decodeTo: BackendTaxSummary.self)
        return report.summary(year: taxYear)
    }

    func updateProfile(firstName: String, lastName: String, defaultStartAddress: String = "") async throws -> AuthUser {
        let body = try encodedMutableBody(["firstName": firstName, "lastName": lastName, "defaultStartAddress": defaultStartAddress])
        let request = try await authenticatedRequest(path: "/api/auth/me", method: "PATCH", body: body)
        let user = try await performAuthenticated(request, decodeTo: AuthUser.self)
        SessionStorage.saveCurrentUser(user)
        return user
    }

    func changePassword(currentPassword: String, newPassword: String) async throws {
        let body = try encodedBody(["currentPassword": currentPassword, "newPassword": newPassword])
        let request = try await authenticatedRequest(path: "/api/auth/password", method: "PATCH", body: body)
        _ = try await performAuthenticated(request, decodeTo: EmptyResponse.self)
    }

    func requestDataExport() async throws -> URL {
        let request = try await authenticatedRequest(path: "/api/account/data-export", method: "POST")
        let (data, response) = try await authenticatedData(request)
        guard !data.isEmpty,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let export = (object["data"] as? [String: Any]) ?? (object["records"] != nil ? object : nil),
              export["records"] is [String: Any], export["generatedAt"] is String else { throw APIError.invalidResponse }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suggested = response.value(forHTTPHeaderField: "Content-Disposition") == nil ? "notary-ledger-export.json" : response.suggestedFilename ?? "notary-ledger-export.json"
        let filename = URL(fileURLWithPath: suggested).lastPathComponent
        let url = directory.appendingPathComponent(filename == "Unknown" ? "notary-ledger-export.json" : filename)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    func fetchAccountDeletion() async throws -> DeletionStatus {
        try await accountDeletion(method: "GET", path: "/api/account/deletion-request")
    }
    func requestAccountDeletion() async throws -> DeletionStatus {
        try await accountDeletion(method: "POST", path: "/api/account/deletion-request")
    }
    func cancelAccountDeletion() async throws -> DeletionStatus {
        try await accountDeletion(method: "POST", path: "/api/account/deletion-cancel")
    }
    private func accountDeletion(method: String, path: String) async throws -> DeletionStatus {
        let request = try await authenticatedRequest(path: path, method: method)
        return try await performAuthenticated(request, decodeTo: DeletionStatus.self)
    }

    func contactSupport(_ payload: SupportContactRequest) async throws {
        let request = try await authenticatedRequest(path: "/api/support/contact", method: "POST", body: encodedMutableBody(payload))
        _ = try await performAuthenticated(request, decodeTo: EmptyResponse.self)
    }

    func logout() async {
        if let request = try? await authenticatedRequest(path: "/api/auth/logout", method: "POST", body: encodedBody(["clientType": "native", "refreshToken": SessionStorage.getRefreshToken() ?? ""])) {
            _ = try? await performAuthenticated(request, decodeTo: EmptyResponse.self)
        }
        SessionStorage.clearSession()
        Self.clearSharedCookies(for: baseURL)
    }

    func fetchCredentials() async throws -> Credentials {
        let request = try await authenticatedRequest(path: "/api/credentials", method: "GET")
        return try await performAuthenticated(request, decodeTo: Credentials.self)
    }

    func updateCredentials(_ credentials: CredentialsPayload) async throws -> Credentials {
        let request = try await authenticatedRequest(path: "/api/credentials", method: "PUT", body: credentials.requestBody())
        return try await performAuthenticated(request, decodeTo: Credentials.self)
    }

    func fetchBillingStatus() async throws -> BillingStatusPayload {
        let request = try await authenticatedRequest(path: "/api/stripe/billing-status", method: "GET")
        return try await performAuthenticated(request, decodeTo: BillingStatusPayload.self)
    }

    func createCheckoutSession(billingInterval: String = "monthly") async throws -> BillingSession {
        let request = try await authenticatedRequest(path: "/api/stripe/checkout-session", method: "POST", body: encodedBody(["billingInterval": billingInterval]))
        return try await performAuthenticated(request, decodeTo: BillingSession.self)
    }

    func createCustomerPortalSession() async throws -> BillingSession {
        let request = try await authenticatedRequest(path: "/api/stripe/customer-portal-session", method: "POST")
        return try await performAuthenticated(request, decodeTo: BillingSession.self)
    }

    func syncCheckoutSession(sessionId: String) async throws -> BillingStatusPayload {
        let body = try encodedMutableBody(["sessionId": sessionId])
        let request = try await authenticatedRequest(path: "/api/stripe/sync-checkout-session", method: "POST", body: body)
        return try await performAuthenticated(request, decodeTo: BillingStatusPayload.self)
    }

    func uploadProfilePhoto(_ file: MultipartFile) async throws -> PhotoResponse {
        try UploadValidation.validate(data: file.data, mimeType: file.mimeType, photo: true)
        let auth = try await authenticatedRequest(path: "/api/auth/me/photo", method: "POST")
        var request = try makeMultipartRequest(path: "/api/auth/me/photo", token: SessionStorage.getAccessToken(), files: [file])
        request.setValue(auth.value(forHTTPHeaderField: "Authorization"), forHTTPHeaderField: "Authorization")
        return try await performAuthenticated(request, decodeTo: PhotoResponse.self)
    }
    func photoAction(uploadId: String? = nil, method: String) async throws -> PhotoResponse {
        let suffix = uploadId.map { "/uploads/" + $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)! } ?? ""
        let request = try await authenticatedRequest(path: "/api/auth/me/photo" + suffix, method: method)
        return try await performAuthenticated(request, decodeTo: PhotoResponse.self)
    }
    func fetchBusinessCard() async throws -> BusinessCard {
        let request = try await authenticatedRequest(path: "/api/business-card/me", method: "GET")
        return try await performAuthenticated(request, decodeTo: CardResponse.self).card
    }
    func saveBusinessCard(_ card: BusinessCard) async throws -> BusinessCard {
        let request = try await authenticatedRequest(path: "/api/business-card/me", method: "PUT", body: card.updateBody())
        return try await performAuthenticated(request, decodeTo: CardResponse.self).card
    }
    func publishBusinessCard(_ publish: Bool) async throws -> BusinessCard {
        let request = try await authenticatedRequest(path: "/api/business-card/me/" + (publish ? "publish" : "unpublish"), method: "POST", body: encodedBody([String: String]()))
        return try await performAuthenticated(request, decodeTo: CardResponse.self).card
    }
    func downloadCardContact(slug: String) async throws -> URL {
        guard slug.range(of: #"^[a-z0-9]+(?:-[a-z0-9]+)*$"#, options: .regularExpression) != nil else { throw APIError.invalidURL }
        let request = try makeRequest(path: "/api/public/cards/\(slug)/contact.vcf", method: "GET")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200...299).contains(http.statusCode) else { throw APIError.httpError(http.statusCode, Self.normalizedErrorMessage(from: data)) }
        guard !data.isEmpty, String(data: data.prefix(64), encoding: .utf8)?.hasPrefix("BEGIN:VCARD") == true else { throw APIError.invalidResponse }
        return try LedgerPDF.save(data: data, filename: slug + ".vcf")
    }
    func fetchAuditLogs(page: Int, action: String = "") async throws -> AuditPage {
        let request = try await authenticatedRequest(path: "/api/admin/audit-logs", method: "GET", queryItems: [URLQueryItem(name: "page", value: String(page)), URLQueryItem(name: "pageSize", value: "25")] + (action.isEmpty ? [] : [URLQueryItem(name: "action", value: action)]))
        return try await performAuthenticated(request, decodeTo: AuditPage.self)
    }
    func importSignings(_ file: MultipartFile) async throws -> SigningImportResult {
        guard !file.data.isEmpty, file.data.count <= 5 * 1024 * 1024,
              ["csv", "tsv", "txt"].contains(URL(fileURLWithPath: file.fileName).pathExtension.lowercased()) else { throw APIError.serverError("Choose a CSV, TSV, or TXT export of 5 MB or smaller.") }
        _ = try await authenticatedRequest(path: "/api/orders/import", method: "POST")
        var request = try makeMultipartRequest(path: "/api/orders/import", token: SessionStorage.getAccessToken(), files: [file])
        request.timeoutInterval = 120
        return try await performAuthenticated(request, decodeTo: SigningImportResult.self)
    }
    func extractSigning(_ file: MultipartFile) async throws -> ExtractedSigning {
        try UploadValidation.validate(data: file.data, mimeType: file.mimeType, photo: false)
        _ = try await authenticatedRequest(path: "/api/orders/extract", method: "POST")
        var request = try makeMultipartRequest(path: "/api/orders/extract", token: SessionStorage.getAccessToken(), files: [file])
        request.timeoutInterval = 120
        return try await performAuthenticated(request, decodeTo: ExtractedSigning.self)
    }
    func extractExpense(_ file: MultipartFile) async throws -> ExtractedExpense {
        try UploadValidation.validate(data: file.data, mimeType: file.mimeType, photo: false)
        guard file.mimeType != "application/pdf" else { throw APIError.serverError("Choose a JPEG, PNG, or WebP receipt image.") }
        _ = try await authenticatedRequest(path: "/api/expenses/extract", method: "POST")
        var request = try makeMultipartRequest(path: "/api/expenses/extract", token: SessionStorage.getAccessToken(), files: [file])
        request.timeoutInterval = 120
        return try await performAuthenticated(request, decodeTo: ExtractedExpense.self)
    }
    func drivingDistance(start: String, destination: String) async throws -> DistanceResponse {
        let request = try await authenticatedRequest(path: "/api/orders/mileage/driving-distance", method: "POST", body: encodedBody(["startAddress": start, "destinationAddress": destination]))
        return try await performAuthenticated(request, decodeTo: DistanceResponse.self)
    }
    func saveMileage(orderId: String, payload: Data) async throws -> SigningOrder {
        let request = try await authenticatedRequest(path: "/api/orders/\(orderId)/mileage", method: "PATCH", body: payload)
        return try await performAuthenticated(request, decodeTo: SigningOrder.self)
    }
    func changeBillingInterval(_ interval: String?) async throws -> BillingStatusPayload {
        let request = try await authenticatedRequest(path: "/api/stripe/change-interval", method: interval == nil ? "DELETE" : "POST", body: try interval.map { try encodedBody(["billingInterval": $0]) })
        return try await performAuthenticated(request, decodeTo: BillingStatusPayload.self)
    }

    func fetchTaxPayments() async throws -> [EstimatedTaxPayment] {
        let request = try await authenticatedRequest(path: "/api/estimated-tax-payments", method: "GET")
        return try await performAuthenticated(request, decodeTo: [EstimatedTaxPayment].self)
    }
    func saveTaxPayment(id: String?, payload: EstimatedTaxPaymentPayload) async throws -> EstimatedTaxPayment {
        let request = try await authenticatedRequest(path: "/api/estimated-tax-payments" + (id.map { "/" + $0 } ?? ""), method: id == nil ? "POST" : "PUT", body: encodedMutableBody(payload))
        return try await performAuthenticated(request, decodeTo: EstimatedTaxPayment.self)
    }
    func deleteTaxPayment(id: String) async throws {
        let request = try await authenticatedRequest(path: "/api/estimated-tax-payments/\(id)", method: "DELETE")
        _ = try await performAuthenticated(request, decodeTo: EmptyResponse.self)
    }
    func fetchOrderExpenses(orderId: String) async throws -> [Expense] {
        let request = try await authenticatedRequest(path: "/api/orders/\(orderId)/expenses", method: "GET")
        return try await performAuthenticated(request, decodeTo: [Expense].self)
    }
    func saveOrderExpense(orderId: String, expenseId: String?, payload: ExpensePayload) async throws -> Expense {
        var object = try JSONSerialization.jsonObject(with: encodedMutableBody(payload)) as! [String: Any]
        object.removeValue(forKey: "businessUsePercent")
        let request = try await authenticatedRequest(path: "/api/orders/\(orderId)/expenses" + (expenseId.map { "/" + $0 } ?? ""), method: expenseId == nil ? "POST" : "PATCH", body: JSONSerialization.data(withJSONObject: object))
        return try await performAuthenticated(request, decodeTo: Expense.self)
    }
    func deleteOrderExpense(orderId: String, expenseId: String) async throws {
        let request = try await authenticatedRequest(path: "/api/orders/\(orderId)/expenses/\(expenseId)", method: "DELETE")
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
            let current = SessionStorage.getAccessToken()
            if current == nil || request.value(forHTTPHeaderField: "Authorization") == current.map({ "Bearer " + $0 }) {
                guard try await refreshSession() else { throw APIError.unauthorized }
            }
            var retry = request
            if let token = SessionStorage.getAccessToken() {
                retry.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            return try await perform(retry, decodeTo: type)
        }
    }

    private func refreshSession() async throws -> Bool {
        if let refreshTask { return try await refreshTask.value }
        let task = Task<Bool, Error> { @MainActor in
            guard let token = SessionStorage.getRefreshToken() else { return false }
            let request = try makeRequest(path: "/api/auth/refresh", method: "POST", body: encodedBody(["clientType": "native", "refreshToken": token]))
            do {
                let response = try await perform(request, decodeTo: AuthResponse.self)
                guard response.refreshToken != nil else { throw APIError.invalidResponse }
                SessionStorage.saveSession(response)
                return true
            } catch APIError.unauthorized {
                SessionStorage.clearTokens()
                return false
            }
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    private func authenticatedData(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        if http.statusCode == 401 {
            guard try await refreshSession(), let token = SessionStorage.getAccessToken() else { throw APIError.unauthorized }
            var retry = request
            retry.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (retryData, retryResponse) = try await session.data(for: retry)
            guard let retryHTTP = retryResponse as? HTTPURLResponse else { throw APIError.invalidResponse }
            guard retryHTTP.statusCode != 401 else { throw APIError.unauthorized }
            guard (200...299).contains(retryHTTP.statusCode) else { throw APIError.httpError(retryHTTP.statusCode, Self.normalizedErrorMessage(from: retryData)) }
            return (retryData, retryHTTP)
        }
        guard (200...299).contains(http.statusCode) else { throw APIError.httpError(http.statusCode, Self.normalizedErrorMessage(from: data)) }
        return (data, http)
    }

    private func perform<T: Decodable>(
        _ request: URLRequest,
        decodeTo type: T.Type,
        allowNotFoundAsEmptyMaintenance: Bool = false
    ) async throws -> T {
        let startedAt = Date()
#if DEBUG
        let method = request.httpMethod ?? "REQUEST"
        let requestURL = request.url?.absoluteString ?? "<invalid URL>"
        print("[API] -> \(method) \(requestURL)")
#endif

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
#if DEBUG
            let elapsed = Date().timeIntervalSince(startedAt)
            print("[API] !! \(method) \(requestURL) failed after \(String(format: "%.2f", elapsed))s: \(error.localizedDescription)")
#endif
            throw error
        }

        guard let httpResponse = response as? HTTPURLResponse else {
#if DEBUG
            print("[API] <- non-HTTP response for \(method) \(requestURL)")
#endif
            throw APIError.invalidResponse
        }
#if DEBUG
        let elapsed = Date().timeIntervalSince(startedAt)
        print("[API] <- \(httpResponse.statusCode) \(method) \(requestURL) in \(String(format: "%.2f", elapsed))s")
        if !(200...299).contains(httpResponse.statusCode) {
            print("[API] Error response:\n\(Self.sanitizedDebugResponseBody(from: data))")
        }
#endif

        if allowNotFoundAsEmptyMaintenance, httpResponse.statusCode == 404, let disabled = MaintenanceStatus.disabled as? T {
            return disabled
        }
        if httpResponse.statusCode == 401 {
            throw APIError.unauthorized
        }
        if !(200...299).contains(httpResponse.statusCode) {
            throw APIError.httpError(httpResponse.statusCode, Self.normalizedErrorMessage(from: data))
        }
        if T.self == EmptyResponse.self {
            return EmptyResponse() as! T
        }
        if data.isEmpty {
            throw APIError.invalidResponse
        }
        return try decodeEnvelopeOrDirect(type, from: data)
    }

    func decodeEnvelopeOrDirect<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        // Inspect wrappers before permissive DTOs can decode an empty/default object.
        if let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if object["success"] as? Bool == false { throw APIError.serverError(Self.normalizedErrorMessage(from: data)) }
            // A user owns its billing details; they are not another response wrapper.
            if type == AuthUser.self, object["id"] != nil || object["_id"] != nil {
                return try decoder.decode(type, from: data)
            }
            for key in ["data", "draft", "billing", "checkoutSession", "portalSession", "user", "summary", "items", "orders", "expenses", "invoice"] {
                if let value = object[key], !(value is NSNull), JSONSerialization.isValidJSONObject(value) {
                    // Collections with pagination and AuthResponse must retain their sibling fields.
                    if key == "user" && (object["accessToken"] != nil || object["token"] != nil) { continue }
                    if key == "items" && object["pagination"] != nil { continue }
                    if key == "orders" && (object["totals"] != nil || object["importedCount"] != nil) { continue }
                    let nested = try JSONSerialization.data(withJSONObject: value)
                    return try decodeEnvelopeOrDirect(type, from: nested)
                }
            }
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
        return "The server could not complete the request."
    }

#if DEBUG
    static func sanitizedDebugResponseBody(from data: Data) -> String {
        guard !data.isEmpty else { return "<empty response body>" }
        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            return "<non-JSON response body omitted>"
        }

        let sanitized = sanitizeDebugJSON(json)
        guard JSONSerialization.isValidJSONObject(sanitized),
              let output = try? JSONSerialization.data(withJSONObject: sanitized, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: output, encoding: .utf8) else {
            return "<unprintable response body>"
        }
        return text
    }

    private static func sanitizeDebugJSON(_ value: Any) -> Any {
        if let dictionary = value as? [String: Any] {
            return dictionary.reduce(into: [String: Any]()) { result, pair in
                result[pair.key] = isSensitiveDebugKey(pair.key)
                    ? "<redacted>"
                    : sanitizeDebugJSON(pair.value)
            }
        }
        if let array = value as? [Any] {
            return array.map { sanitizeDebugJSON($0) }
        }
        if let string = value as? String {
            return redactTokenPatterns(in: string)
        }
        return value
    }

    private static func isSensitiveDebugKey(_ key: String) -> Bool {
        let normalized = key.lowercased().filter(\.isLetter)
        return normalized.contains("password")
            || normalized.contains("token")
            || normalized.contains("authorization")
            || normalized.contains("cookie")
            || normalized.contains("secret")
            || normalized.contains("sessionid")
    }

    private static func redactTokenPatterns(in value: String) -> String {
        let patterns = [
            #"(?i)bearer\s+[A-Za-z0-9._~+\/-]+=*"#,
            #"\b[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b"#
        ]
        return patterns.reduce(value) { result, pattern in
            result.replacingOccurrences(of: pattern, with: "<redacted>", options: .regularExpression)
        }
    }
#endif

    static func sanitizedMutablePayload(_ value: Any) -> Any {
        let unsafeKeys: Set<String> = [
            "userId",
            "ownerId",
            "createdById",
            "organizationId",
            "role",
            "isAdmin",
            "passwordHash",
            "emailVerifiedAt",
            "createdAt",
            "updatedAt"
        ]

        if let dictionary = value as? [String: Any] {
            return dictionary.reduce(into: [String: Any]()) { result, pair in
                guard !unsafeKeys.contains(pair.key) else { return }
                result[pair.key] = sanitizedMutablePayload(pair.value)
            }
        }
        if let array = value as? [Any] {
            return array.map { sanitizedMutablePayload($0) }
        }
        return value
    }

    private static func clearSharedCookies(for baseURL: String) {
        guard let url = URL(string: baseURL), let cookies = HTTPCookieStorage.shared.cookies(for: url) else { return }
        cookies.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
    }

    private func clearCookiesForPublicAuth() {
        Self.clearSharedCookies(for: baseURL)
    }
}

private struct BackendError: Decodable {
    struct ErrorPayload: Decodable {
        let code: String?
        let message: String?
        var details: [FieldDetail]? = nil
        var rows: [RowError]? = nil
        struct RowError: Decodable { let row: Int; let message: String }
        enum CodingKeys: String, CodingKey { case code, message, details, rows }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            code = try c.decodeIfPresent(String.self, forKey: .code)
            message = try c.decodeIfPresent(String.self, forKey: .message)
            details = try? c.decodeIfPresent([FieldDetail].self, forKey: .details)
            rows = try? c.decodeIfPresent([RowError].self, forKey: .rows)
        }
    }
    struct FieldDetail: Decodable { let field: String?; let message: String }

    let message: String?
    let error: ErrorPayload?
    let errorText: String?
    let errors: [String]?
    let fieldErrors: [String: [String]]?

    enum CodingKeys: String, CodingKey {
        case message
        case error
        case errors
        case fieldErrors
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        error = try? container.decodeIfPresent(ErrorPayload.self, forKey: .error)
        errorText = try? container.decodeIfPresent(String.self, forKey: .error)
        errors = try container.decodeIfPresent([String].self, forKey: .errors)
        fieldErrors = try container.decodeIfPresent([String: [String]].self, forKey: .fieldErrors)
    }

    var displayMessage: String {
        if let message, !message.isEmpty { return message }
        if let rows = error?.rows, !rows.isEmpty { return rows.map { "Row \($0.row): \($0.message)" }.joined(separator: "\n") }
        if let details = error?.details, !details.isEmpty { return details.map { ($0.field.map { $0 + ": " } ?? "") + $0.message }.joined(separator: "\n") }
        if let message = error?.message, !message.isEmpty { return message }
        if let errorText, !errorText.isEmpty { return errorText }
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

struct MultipartFile {
    var fieldName: String
    var fileName: String
    var mimeType: String
    var data: Data
}

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
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

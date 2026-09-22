import Foundation

#if canImport(Testing)
import Testing
@testable import notaryledger_ios

struct ValidationAndAPITests {
    @Test func passwordValidationRequiresLengthAndComplexity() {
        #expect(PasswordValidation.message(for: "Short1!") == "Use at least 12 characters.")
        #expect(PasswordValidation.message(for: "            ") == "Password cannot be only whitespace.")
        #expect(PasswordValidation.message(for: "alllowercasepassword") == "Use at least 3 of lowercase, uppercase, number, and symbol.")
        #expect(PasswordValidation.message(for: "StrongPass12!") == nil)
    }

    @Test func apiRequestBuildsExpectedURLHeadersAndJSONBody() throws {
        let service = APIService(baseURL: "https://api.example.test/")
        let payload = SupportContactRequest(
            name: "Avery Notary",
            email: "avery@example.com",
            topic: "Invoices",
            subject: "Question",
            message: "Need help with an invoice.",
            sourcePage: "Profile"
        )

        let request = try service.makeRequest(
            path: "/api/support/contact",
            method: "POST",
            token: "access-token",
            body: service.encodedBody(payload)
        )

        #expect(request.url?.absoluteString == "https://api.example.test/api/support/contact")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-token")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

        let object = try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? [String: Any]
        #expect(object?["email"] as? String == "avery@example.com")
        #expect(object?["sourcePage"] as? String == "Profile")
    }

    @Test func stagingBaseURLBuildsOrdersEndpointWithoutDuplicatingAPI() throws {
        let service = APIService(baseURL: "https://api-stage.notaryledger.org")
        let request = try service.makeRequest(path: "/api/orders", method: "GET")

        #expect(request.url?.absoluteString == "https://api-stage.notaryledger.org/api/orders")
    }

    @Test func stagingAuthURLsUseCanonicalHost() throws {
        #if STAGING
        #expect(APIConfig.baseURL == "https://api-stage.notaryledger.org")
        #endif
        let service = APIService(baseURL: "https://api-stage.notaryledger.org")
        let login = try service.makeRequest(path: "/api/auth/login", method: "POST")
        let registration = try service.makeRequest(path: "/api/auth/register", method: "POST")

        #expect(login.url?.absoluteString == "https://api-stage.notaryledger.org/api/auth/login")
        #expect(registration.url?.absoluteString == "https://api-stage.notaryledger.org/api/auth/register")
    }

    @Test func defaultSessionUsesServerManagedRefreshCookieHandling() {
        let configuration = APIService.defaultSessionConfiguration()

        #expect(configuration.httpShouldSetCookies == true)
        #expect(configuration.httpCookieAcceptPolicy == .always)
        #expect(configuration.httpCookieStorage === HTTPCookieStorage.shared)
    }

#if DEBUG
    @Test func debugErrorResponseLoggingRedactsSecrets() throws {
        let json = """
        {
          "error": "Forbidden",
          "message": "Authorization failed for Bearer visible-secret",
          "code": "CSRF_FAILED",
          "accessToken": "access-secret",
          "nested": {
            "refresh_token": "refresh-secret",
            "password": "password-secret",
            "cookie": "cookie-secret",
            "detail": "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1c2VyLTEifQ.signaturevalue"
          }
        }
        """.data(using: .utf8)!

        let output = APIService.sanitizedDebugResponseBody(from: json)

        #expect(output.contains(#""error" : "Forbidden""#))
        #expect(output.contains(#""code" : "CSRF_FAILED""#))
        #expect(output.contains("<redacted>"))
        #expect(!output.contains("visible-secret"))
        #expect(!output.contains("access-secret"))
        #expect(!output.contains("refresh-secret"))
        #expect(!output.contains("password-secret"))
        #expect(!output.contains("cookie-secret"))
        #expect(!output.contains("eyJhbGci"))
    }

    @Test func debugErrorResponseLoggingOmitsNonJSONBodies() {
        let data = Data("upstream token=secret".utf8)
        #expect(APIService.sanitizedDebugResponseBody(from: data) == "<non-JSON response body omitted>")
    }
#endif

    @Test func authResponseNormalizesAccessTokenAndIgnoresRefreshToken() throws {
        let json = """
        {
          "success": true,
          "data": {
            "accessToken": "access-token",
            "refreshToken": "server-cookie-only",
            "user": {
              "id": "user-1",
              "firstName": "Avery",
              "lastName": "Notary",
              "email": "avery@example.com"
            }
          }
        }
        """.data(using: .utf8)!

        let response = try APIService(baseURL: "https://api.example.test").decodeEnvelopeOrDirect(AuthResponse.self, from: json)

        #expect(response.token == "access-token")
        #expect(response.user?.displayFirstName == "Avery")
        #expect(response.user?.displayLastName == "Notary")
    }

    @Test func registrationHandlesEmailVerificationResponse() async throws {
        MockURLProtocol.requests = []
        MockURLProtocol.requestHandler = { request in
            #expect(request.url?.path == "/api/auth/register")
            #expect(request.timeoutInterval == 90)
            return MockURLProtocol.jsonResponse(
                for: request,
                statusCode: 201,
                body: #"{"success":true,"data":{"emailVerificationRequired":true,"message":"Check your email to verify your account."}}"#
            )
        }
        defer {
            MockURLProtocol.requestHandler = nil
            MockURLProtocol.requests = []
        }

        let result = try await APIService(baseURL: "https://api.example.test", session: MockURLProtocol.session()).register(
            firstName: "Avery",
            lastName: "Notary",
            email: "avery@example.com",
            password: "StrongPass12!"
        )

        guard case .verificationRequired(let message) = result else {
            Issue.record("Expected registration to require email verification")
            return
        }
        #expect(message == "Check your email to verify your account.")
    }

    @Test func resendVerificationUsesRecoveryEndpoint() async throws {
        MockURLProtocol.requests = []
        MockURLProtocol.requestHandler = { request in
            #expect(request.url?.path == "/api/auth/resend-verification")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
            return MockURLProtocol.jsonResponse(
                for: request,
                body: #"{"success":true,"data":{"message":"If this email can be registered, verification instructions have been sent."}}"#
            )
        }
        defer {
            MockURLProtocol.requestHandler = nil
            MockURLProtocol.requests = []
        }

        try await APIService(baseURL: "https://api.example.test", session: MockURLProtocol.session())
            .resendVerification(email: "avery@example.com")
    }

    @Test func registrationClearsStaleRefreshCookieBeforeRequest() async throws {
        let baseURL = "https://api.example.test"
        let cookie = try #require(HTTPCookie(properties: [
            .domain: "api.example.test",
            .path: "/",
            .name: "notary_refresh_token",
            .value: "stale-token",
            .secure: "TRUE",
        ]))
        HTTPCookieStorage.shared.setCookie(cookie)

        MockURLProtocol.requests = []
        MockURLProtocol.requestHandler = { request in
            #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
            return MockURLProtocol.jsonResponse(
                for: request,
                statusCode: 201,
                body: #"{"success":true,"data":{"emailVerificationRequired":true}}"#
            )
        }
        defer {
            HTTPCookieStorage.shared.deleteCookie(cookie)
            MockURLProtocol.requestHandler = nil
            MockURLProtocol.requests = []
        }

        _ = try await APIService(baseURL: baseURL, session: MockURLProtocol.session()).register(
            firstName: "Avery",
            lastName: "Notary",
            email: "avery@example.com",
            password: "StrongPass12!"
        )
    }

    @Test func appLaunchRefreshRestoresSessionAndLoadsCurrentUser() async throws {
        SessionStorage.clearSession()
        MockURLProtocol.requests = []
        MockURLProtocol.requestHandler = { request in
            switch (request.httpMethod, request.url?.path) {
            case ("POST"?, "/api/auth/refresh"):
                return MockURLProtocol.jsonResponse(for: request, body: #"{"success":true,"data":{"token":"fresh-token"}}"#)
            case ("GET"?, "/api/config/maintenance"):
                return MockURLProtocol.jsonResponse(for: request, body: #"{"enabled":false}"#)
            case ("GET"?, "/api/auth/me"):
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fresh-token")
                return MockURLProtocol.jsonResponse(for: request, body: #"{"success":true,"data":{"id":"user-1","firstName":"Avery","lastName":"Notary","email":"avery@example.com"}}"#)
            default:
                return MockURLProtocol.jsonResponse(for: request, statusCode: 404, body: #"{}"#)
            }
        }
        defer {
            SessionStorage.clearSession()
            MockURLProtocol.requestHandler = nil
            MockURLProtocol.requests = []
        }

        let user = try await APIService(baseURL: "https://api.example.test", session: MockURLProtocol.session()).restoreSession()

        #expect(user.email == "avery@example.com")
        #expect(SessionStorage.getAccessToken() == "fresh-token")
    }

    @Test func authenticatedRequest401RefreshesOnceThenRetriesOriginalRequest() async throws {
        SessionStorage.clearSession()
        SessionStorage.saveAccessToken("expired-token")
        MockURLProtocol.requests = []
        MockURLProtocol.requestHandler = { request in
            switch (request.httpMethod, request.url?.path) {
            case ("GET"?, "/api/config/maintenance"):
                return MockURLProtocol.jsonResponse(for: request, body: #"{"enabled":false}"#)
            case ("GET"?, "/api/orders") where request.value(forHTTPHeaderField: "Authorization") == "Bearer expired-token":
                return MockURLProtocol.jsonResponse(for: request, statusCode: 401, body: #"{"message":"Unauthorized"}"#)
            case ("POST"?, "/api/auth/refresh"):
                #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
                #expect(request.httpBody == nil)
                return MockURLProtocol.jsonResponse(for: request, body: #"{"success":true,"data":{"accessToken":"fresh-token"}}"#)
            case ("GET"?, "/api/orders") where request.value(forHTTPHeaderField: "Authorization") == "Bearer fresh-token":
                return MockURLProtocol.jsonResponse(for: request, body: #"{"success":true,"data":[]}"#)
            default:
                return MockURLProtocol.jsonResponse(for: request, statusCode: 500, body: #"{"message":"Unexpected request"}"#)
            }
        }
        defer {
            SessionStorage.clearSession()
            MockURLProtocol.requestHandler = nil
            MockURLProtocol.requests = []
        }

        let orders = try await APIService(baseURL: "https://api.example.test", session: MockURLProtocol.session()).fetchOrders()

        #expect(orders.isEmpty)
        #expect(SessionStorage.getAccessToken() == "fresh-token")
        #expect(MockURLProtocol.requests.filter { $0.url?.path == "/api/auth/refresh" }.count == 1)
    }

    @Test func logoutClearsLocalAccessToken() async {
        SessionStorage.saveAccessToken("access-token")
        MockURLProtocol.requests = []
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(for: request, body: #"{}"#)
        }
        defer {
            SessionStorage.clearSession()
            MockURLProtocol.requestHandler = nil
            MockURLProtocol.requests = []
        }

        await APIService(baseURL: "https://api.example.test", session: MockURLProtocol.session()).logout()

        #expect(SessionStorage.getAccessToken() == nil)
    }

    @Test func ordersAndExpensesUseAuthoritativeAPIPaths() throws {
        let service = APIService(baseURL: "https://api.example.test")
        let order = try service.makeRequest(path: "/api/orders/order-1", method: "PUT")
        let mileage = try service.makeRequest(path: "/api/orders/order-1/mileage", method: "PATCH")
        let expense = try service.makeRequest(path: "/api/expenses/expense-1", method: "DELETE")

        #expect(order.url?.absoluteString == "https://api.example.test/api/orders/order-1")
        #expect(mileage.url?.absoluteString == "https://api.example.test/api/orders/order-1/mileage")
        #expect(expense.url?.absoluteString == "https://api.example.test/api/expenses/expense-1")
    }
}

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.requests.append(request)
        guard let requestHandler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: APIError.invalidResponse)
            return
        }
        do {
            let (response, data) = try requestHandler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func session() -> URLSession {
        let configuration = APIService.defaultSessionConfiguration()
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    static func jsonResponse(for request: URLRequest, statusCode: Int = 200, body: String) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, Data(body.utf8))
    }
}
#endif

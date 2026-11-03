import Foundation

#if canImport(Testing)
import Testing
@testable import notaryledger_ios

@MainActor
@Suite(.serialized)
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

    @Test func credentialsEditorLoadsAndSavesThroughTheAuthenticatedAPI() async throws {
        let previousToken = SessionStorage.getAccessToken()
        SessionStorage.saveAccessToken("credential-fixture-token")
        MockURLProtocol.requests = []
        defer {
            MockURLProtocol.requestHandler = nil
            MockURLProtocol.requests = []
            if let previousToken { SessionStorage.saveAccessToken(previousToken) } else { SessionStorage.clearTokens() }
        }
        MockURLProtocol.requestHandler = { request in
            if request.url?.path == "/api/config/maintenance" {
                return MockURLProtocol.jsonResponse(for: request, body: #"{"enabled":false}"#)
            }
            #expect(request.url?.path == "/api/credentials")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer credential-fixture-token")
            if request.httpMethod == "GET" {
                return MockURLProtocol.jsonResponse(for: request, body: #"{"success":true,"data":{"commissionNumber":"CA123","commissionState":"CA","commissionExpirationDate":"2027-01-31T00:00:00.000Z","eoProvider":"Example Insurance","eoCoverageAmount":"25000.50","eoExpirationDate":"2027-06-01"}}"#)
            }
            #expect(request.httpMethod == "PUT")
            let body = try #require(request.httpBody)
            let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(json["commissionNumber"] is NSNull)
            #expect(json["commissionState"] is NSNull)
            #expect(json["commissionExpirationDate"] is NSNull)
            #expect(json["eoCoverageAmount"] as? Double == 75000.50)
            return MockURLProtocol.jsonResponse(for: request, body: #"{"success":true,"data":{"commissionNumber":null,"commissionState":null,"commissionExpirationDate":null,"eoProvider":"Example Insurance","eoCoverageAmount":"75000.50","eoExpirationDate":"2027-06-01T00:00:00.000Z"}}"#)
        }
        let service = APIService(baseURL: "https://credentials.example.test", session: MockURLProtocol.session())
        let model = CredentialsEditorModel(fetch: { try await service.fetchCredentials() }, persist: { try await service.updateCredentials($0) })
        await model.load()
        #expect(model.error.isEmpty && model.canEdit)
        #expect(model.draft.commissionExpirationDate == "2027-01-31")
        for field in CredentialSection.commission.fields { model.edit(field, value: "") }
        let coverage = try #require(CredentialSection.insurance.fields.first { $0.id == "eoCoverageAmount" })
        model.edit(coverage, value: "75000.50")
        await model.save()
        #expect(model.error.isEmpty && !model.success.isEmpty)
        #expect(model.saved?.eoCoverageAmount == "75000.50")
        #expect(model.saved?.eoExpirationDate == "2027-06-01")
        #expect(model.addedSections == [.insurance])
        #expect(!model.hasChanges)
        #expect(MockURLProtocol.requests.filter { $0.httpMethod == "PUT" }.count == 1)
    }

    @Test func profileUpdateDecodesUserWithBillingAndPersistsIt() async throws {
        SessionStorage.saveAccessToken("access-token")
        MockURLProtocol.requests = []
        defer {
            SessionStorage.clearSession()
            MockURLProtocol.requestHandler = nil
            MockURLProtocol.requests = []
        }
        MockURLProtocol.requestHandler = { request in
            if request.url?.path == "/api/config/maintenance" {
                return MockURLProtocol.jsonResponse(for: request, body: #"{"enabled":false}"#)
            }
            #expect(request.url?.path == "/api/auth/me")
            #expect(request.httpMethod == "PATCH")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-token")
            let requestBody = try #require(request.httpBody)
            let body = try #require(JSONSerialization.jsonObject(with: requestBody) as? [String: String])
            #expect(body == ["firstName": "Updated", "lastName": "Notary", "defaultStartAddress": ""])
            return MockURLProtocol.jsonResponse(for: request, body: #"{"success":true,"data":{"user":{"id":"u1","firstName":"Updated","lastName":"Notary","fullName":"Updated Notary","email":"a@example.test","role":"NOTARY","defaultStartAddress":null,"profilePhotoUrl":null,"profilePhotoUpload":null,"billing":{"plan":"FREE","subscriptionStatus":"INACTIVE"}}}}"#)
        }
        let api = APIService(baseURL: "https://api.example.test", session: MockURLProtocol.session())
        let user = try await api.updateProfile(firstName: "Updated", lastName: "Notary")
        #expect(user.id == "u1")
        #expect(user.displayFirstName == "Updated")
        #expect(user.defaultStartAddress == nil)
        #expect(SessionStorage.getCurrentUser() == user)
        #expect(MockURLProtocol.requests.filter { $0.httpMethod == "PATCH" }.count == 1)
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

    @Test func defaultSessionUsesCookieFreeNativeAuthentication() {
        let configuration = APIService.defaultSessionConfiguration()

        #expect(configuration.httpShouldSetCookies == false)
        #expect(configuration.httpCookieAcceptPolicy == .always)
        #expect(configuration.httpCookieStorage == nil)
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

    @Test func authResponseDecodesNativeTokens() throws {
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
        #expect(response.refreshToken == "server-cookie-only")
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
        SessionStorage.saveSession(try JSONDecoder().decode(AuthResponse.self, from: Data(#"{"accessToken":"expired-token","refreshToken":"old-refresh"}"#.utf8)))
        MockURLProtocol.requests = []
        MockURLProtocol.requestHandler = { request in
            switch (request.httpMethod, request.url?.path) {
            case ("POST"?, "/api/auth/refresh"):
                return MockURLProtocol.jsonResponse(for: request, body: #"{"success":true,"data":{"token":"fresh-token","refreshToken":"rotated-refresh"}}"#)
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
        SessionStorage.saveSession(try JSONDecoder().decode(AuthResponse.self, from: Data(#"{"accessToken":"expired-token","refreshToken":"old-refresh"}"#.utf8)))
        MockURLProtocol.requests = []
        MockURLProtocol.requestHandler = { request in
            switch (request.httpMethod, request.url?.path) {
            case ("GET"?, "/api/config/maintenance"):
                return MockURLProtocol.jsonResponse(for: request, body: #"{"enabled":false}"#)
            case ("GET"?, "/api/orders") where request.value(forHTTPHeaderField: "Authorization") == "Bearer expired-token":
                return MockURLProtocol.jsonResponse(for: request, statusCode: 401, body: #"{"message":"Unauthorized"}"#)
            case ("POST"?, "/api/auth/refresh"):
                #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
                let body = try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? [String: String]
                #expect(body?["clientType"] == "native")
                #expect(body?["refreshToken"] == "old-refresh")
                return MockURLProtocol.jsonResponse(for: request, body: #"{"success":true,"data":{"accessToken":"fresh-token","refreshToken":"rotated-refresh"}}"#)
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

    @Test func nativeLoginSendsNoCookiesAndPersistsRotatedCredentials() async throws {
        SessionStorage.clearSession()
        defer { SessionStorage.clearSession(); MockURLProtocol.requestHandler = nil }
        MockURLProtocol.requestHandler = { request in
            #expect(request.url?.path == "/api/auth/login")
            #expect(!request.httpShouldHandleCookies)
            let bytes = try #require(request.httpBody)
            let body = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: String])
            #expect(body["clientType"] == "native")
            return MockURLProtocol.jsonResponse(for: request, body: #"{"success":true,"data":{"accessToken":"a","refreshToken":"r","user":{"id":"u","email":"a@example.test"}}}"#)
        }
        _ = try await APIService(baseURL: "https://api.example.test", session: MockURLProtocol.session()).login(email: "a@example.test", password: "password")
        #expect(SessionStorage.getAccessToken() == "a")
        #expect(SessionStorage.getRefreshToken() == "r")
    }

    @Test func exportPreservesReturnedBytesAndRefreshesOnce() async throws {
        let auth = try JSONDecoder().decode(AuthResponse.self, from: Data(#"{"accessToken":"expired-token","refreshToken":"refresh-token"}"#.utf8))
        SessionStorage.saveSession(auth)
        MockURLProtocol.requests = []
        defer { SessionStorage.clearSession(); MockURLProtocol.requestHandler = nil; MockURLProtocol.requests = [] }
        let exported = #"{"success":true,"data":{"generatedAt":"2026-11-01","records":{"orders":[{"id":"o1"}]}}}"#
        MockURLProtocol.requestHandler = { request in
            switch request.url?.path {
            case "/api/config/maintenance": return MockURLProtocol.jsonResponse(for: request, body: #"{"enabled":false}"#)
            case "/api/auth/refresh": return MockURLProtocol.jsonResponse(for: request, body: #"{"success":true,"data":{"accessToken":"fresh-token","refreshToken":"rotated"}}"#)
            case "/api/account/data-export":
                if request.value(forHTTPHeaderField: "Authorization") == "Bearer expired-token" { return MockURLProtocol.jsonResponse(for: request, statusCode: 401, body: #"{"message":"Expired"}"#) }
                return MockURLProtocol.jsonResponse(for: request, body: exported)
            default: throw APIError.invalidResponse
            }
        }
        let file = try await APIService(baseURL: "https://api.example.test", session: MockURLProtocol.session()).requestDataExport()
        #expect(file.pathExtension == "json")
        #expect(try Data(contentsOf: file) == Data(exported.utf8))
        #expect(MockURLProtocol.requests.filter { $0.url?.path == "/api/auth/refresh" }.count == 1)
        try FileManager.default.removeItem(at: file.deletingLastPathComponent())
    }

    @Test func photoUploadAndScanUseBackendMultipartAndStatusContracts() async throws {
        SessionStorage.saveAccessToken("access-token")
        defer { SessionStorage.clearSession(); MockURLProtocol.requestHandler = nil }
        MockURLProtocol.requestHandler = { request in
            switch (request.httpMethod, request.url?.path) {
            case (_, "/api/config/maintenance"): return MockURLProtocol.jsonResponse(for: request, body: #"{"enabled":false}"#)
            case ("POST"?, "/api/auth/me/photo"):
                #expect(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
                let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
                #expect(body.contains("name=\"photo\"; filename=\"photo.png\""))
                return MockURLProtocol.jsonResponse(for: request, statusCode: 202, body: #"{"success":true,"data":{"profilePhotoUrl":null,"upload":{"id":"upload-1","status":"SCANNING"}}}"#)
            case ("GET"?, "/api/auth/me/photo/uploads/upload-1"):
                return MockURLProtocol.jsonResponse(for: request, body: #"{"success":true,"data":{"profilePhotoUrl":"https://photo.example/me.webp","upload":{"id":"upload-1","status":"COMPLETED"}}}"#)
            case ("DELETE"?, "/api/auth/me/photo"):
                #expect(request.httpBody == nil)
                return MockURLProtocol.jsonResponse(for: request, body: #"{"success":true,"data":{"profilePhotoUrl":null}}"#)
            default: throw APIError.invalidResponse
            }
        }
        let api = APIService(baseURL: "https://api.example.test", session: MockURLProtocol.session())
        let pending = try await api.uploadProfilePhoto(MultipartFile(fieldName: "photo", fileName: "photo.png", mimeType: "image/png", data: Data([137, 80, 78, 71])))
        #expect(pending.upload?.isPending == true)
        let completed = try await api.photoAction(uploadId: "upload-1", method: "GET")
        #expect(completed.upload?.status == "COMPLETED")
        #expect(completed.profilePhotoUrl != nil)
        #expect(try await api.photoAction(method: "DELETE").profilePhotoUrl == nil)
    }

    @Test func signingExtractionSurfacesFailureWithoutCreatingAnOrder() async throws {
        SessionStorage.saveAccessToken("access-token")
        MockURLProtocol.requests = []
        defer { SessionStorage.clearSession(); MockURLProtocol.requestHandler = nil; MockURLProtocol.requests = [] }
        MockURLProtocol.requestHandler = { request in
            if request.url?.path == "/api/config/maintenance" { return MockURLProtocol.jsonResponse(for: request, body: #"{"enabled":false}"#) }
            #expect(request.url?.path == "/api/orders/extract")
            return MockURLProtocol.jsonResponse(for: request, statusCode: 422, body: #"{"success":false,"error":{"message":"Could not extract signing details from this file."}}"#)
        }
        do {
            _ = try await APIService(baseURL: "https://api.example.test", session: MockURLProtocol.session()).extractSigning(MultipartFile(fieldName: "file", fileName: "order.pdf", mimeType: "application/pdf", data: Data([37, 80, 68, 70])))
            Issue.record("Extraction must fail")
        } catch { #expect(error.localizedDescription == "Could not extract signing details from this file.") }
        #expect(!MockURLProtocol.requests.contains { $0.url?.path == "/api/orders" })
    }

    @Test func spreadsheetImportUsesMultipartAndReturnsOnlyServerSavedOrders() async throws {
        SessionStorage.saveAccessToken("access-token")
        defer { SessionStorage.clearSession(); MockURLProtocol.requestHandler = nil }
        MockURLProtocol.requestHandler = { request in
            if request.url?.path == "/api/config/maintenance" { return MockURLProtocol.jsonResponse(for: request, body: #"{"enabled":false}"#) }
            #expect(request.url?.path == "/api/orders/import")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data") == true)
            let data = try #require(request.httpBody)
            #expect(String(decoding: data, as: UTF8.self).contains("signings.csv"))
            return MockURLProtocol.jsonResponse(for: request, statusCode: 201, body: #"{"success":true,"data":{"importedCount":0,"skippedDuplicateCount":1,"orders":[]}}"#)
        }
        let result = try await APIService(baseURL: "https://api.example.test", session: MockURLProtocol.session()).importSignings(MultipartFile(fieldName: "file", fileName: "signings.csv", mimeType: "text/csv", data: Data("Customer,Signer,Date,Fee\nAcme,Avery,2026-11-01,100".utf8)))
        #expect(result.importedCount == 0)
        #expect(result.skippedDuplicateCount == 1)
        #expect(result.orders.isEmpty)
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
        var observed = request
        if observed.httpBody == nil, let stream = observed.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var body = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                body.append(buffer, count: count)
            }
            observed.httpBody = body
        }
        Self.requests.append(observed)
        guard let requestHandler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: APIError.invalidResponse)
            return
        }
        do {
            let (response, data) = try requestHandler(observed)
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

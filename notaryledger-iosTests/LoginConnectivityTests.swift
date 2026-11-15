import Foundation
import Testing
@testable import notaryledger_ios

extension ValidationAndAPITests {
    // Run this same test in Debug and Release; do not gate the assertion on a
    // compile flag in the test bundle, which hid the original Release bug.
    @Test func stagingApplicationUsesStagingAPIInEveryConfiguration() throws {
        if Bundle.main.bundleIdentifier == "org.notaryledger.app.staging" {
            #expect(APIConfig.environment == .staging)
            #expect(APIConfig.baseURL == "https://api-stage.notaryledger.org")
            let request = try APIService().makeRequest(path: "/api/auth/login", method: "POST")
            #expect(request.url?.absoluteString == "https://api-stage.notaryledger.org/api/auth/login")
        }
    }

    @Test func loginURLHasExactlyOneAPIPrefixAndHandlesTrailingSlash() throws {
        for base in ["https://api-stage.notaryledger.org", "https://api-stage.notaryledger.org/"] {
            for path in ["/api/auth/login", "api/auth/login"] {
                let request = try APIService(baseURL: base).makeRequest(path: path, method: "POST")
                #expect(request.url?.absoluteString == "https://api-stage.notaryledger.org/api/auth/login")
                #expect(request.timeoutInterval == 30)
            }
        }
    }

    @Test func loginTransportFailuresAreSafeAndDistinctFromHTTPFailures() async {
        defer {
            MockURLProtocol.requestHandler = nil
            MockURLProtocol.requests = []
            SessionStorage.clearSession()
        }
        for code in [URLError.cannotConnectToHost, .cannotFindHost, .timedOut, .secureConnectionFailed,
                     .serverCertificateUntrusted, .appTransportSecurityRequiresSecureConnection, .notConnectedToInternet] {
            SessionStorage.clearSession()
            MockURLProtocol.requestHandler = { _ in
                throw URLError(code, userInfo: [NSLocalizedDescriptionKey: "secret@example.test token=secret"])
            }
            let api = APIService(session: MockURLProtocol.session())
            let model = AuthFlowModel(api: api)
            model.email = "fixture@example.test"; model.password = "fixture-secret"
            await model.submit(authenticate: { _ in Issue.record("Transport failure must not authenticate") })
            #expect(model.error == LoginFailure.transport(code.rawValue).localizedDescription)
            #expect(!model.error.contains("secret"))
            #expect(model.diagnosticCode == (APIConfig.environment == .staging ? "NL-NET-\(abs(code.rawValue))" : nil))
            #expect(SessionStorage.getAccessToken() == nil)
            model.navigate(.login)
            #expect(model.diagnosticCode == nil)
        }
        #expect(LoginDiagnostics.urlErrorCode(NSError(domain: "private-domain", code: 999, userInfo: [:])) == nil)
    }

    @Test func loginHTTPStatusAndDecodingFailuresRemainDistinct() async {
        defer {
            MockURLProtocol.requestHandler = nil
            MockURLProtocol.requests = []
            SessionStorage.clearSession()
        }
        for (status, body) in [(401, #"{"message":"Invalid credentials."}"#),
                               (403, #"{"message":"Please verify your email."}"#),
                               (500, "<html>upstream failure</html>"), (503, "{}"),
                               (200, "invalid JSON"), (200, "{}"), (200, "")] {
            SessionStorage.clearSession()
            MockURLProtocol.requestHandler = { MockURLProtocol.jsonResponse(for: $0, statusCode: status, body: body) }
            let model = AuthFlowModel(api: APIService(session: MockURLProtocol.session()))
            model.email = "fixture@example.test"; model.password = "fixture-secret"
            await model.submit(authenticate: { _ in Issue.record("Failed login must not authenticate") })
            let expectedCode = status != 200 ? "NL-HTTP-\(status)" : body.isEmpty ? "NL-RESPONSE" : "NL-DECODE"
            #expect(model.diagnosticCode == (APIConfig.environment == .staging ? expectedCode : nil))
            #expect(!model.error.contains("Could not connect"))
            #expect(!model.isSubmitting)
            #expect(SessionStorage.getAccessToken() == nil)
        }
    }
}

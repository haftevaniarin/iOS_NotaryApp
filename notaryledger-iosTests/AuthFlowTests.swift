import Foundation
import Testing
@testable import notaryledger_ios

// Keep transport fixtures serialized with the existing API contract tests.
extension ValidationAndAPITests {
    private func authModel(_ screen: AuthScreen = .login, token: String = "", status: Int = 200, body: String = "{}") -> AuthFlowModel {
        SessionStorage.clearSession()
        MockURLProtocol.requests = []
        MockURLProtocol.requestHandler = { MockURLProtocol.jsonResponse(for: $0, statusCode: status, body: body) }
        return AuthFlowModel(screen: screen, token: token, api: APIService(baseURL: "https://auth.example.test", session: MockURLProtocol.session()))
    }
    private func validSignup(_ model: AuthFlowModel) {
        model.firstName = " Avery "; model.lastName = " Notary "; model.email = " avery@example.test "
        model.password = "StrongPass12!"; model.confirmPassword = "StrongPass12!"
    }
    private func clearAuthFixture() {
        MockURLProtocol.requestHandler = nil; MockURLProtocol.requests = []; SessionStorage.clearSession()
    }

    @Test func loginValidationMatchesWebAndDoesNotCallServer() async {
        let model = authModel()
        defer { clearAuthFixture() }
        await model.submit(authenticate: { _ in Issue.record("Unexpected login") })
        #expect(model.error == "Please enter your email.")
        model.email = "avery@example.test"
        await model.submit(authenticate: { _ in Issue.record("Unexpected login") })
        #expect(model.error == "Please enter your password.")
        #expect(MockURLProtocol.requests.isEmpty)
    }

    @Test func signupValidatesBothNamesEmailPasswordAndConfirmationInWebOrder() async {
        let model = authModel(.signup)
        defer { clearAuthFixture() }
        await model.submit(authenticate: { _ in })
        #expect(model.fieldErrors == ["firstName": "Please enter your first name.", "lastName": "Please enter your last name."])
        model.firstName = String(repeating: "A", count: 101); model.lastName = "Notary"
        await model.submit(authenticate: { _ in })
        #expect(model.fieldErrors["firstName"] == "First name must be 100 characters or less.")
        model.firstName = "Avery"
        await model.submit(authenticate: { _ in })
        #expect(model.error == "Please enter your email.")
        model.email = "avery@example"
        await model.submit(authenticate: { _ in })
        #expect(model.error == "Please enter a valid email address.")
        model.email = "avery@example.test"; model.password = "abcdefghij1 "
        await model.submit(authenticate: { _ in })
        #expect(model.error == AuthCopy.passwordRequirements, "A space does not count as a symbol on the web")
        model.password = "StrongPass12!"; model.confirmPassword = "different"
        await model.submit(authenticate: { _ in })
        #expect(model.error == "Passwords do not match.")
        #expect(MockURLProtocol.requests.isEmpty)
    }

    @Test func verificationRequiredSignupLandsOnLoginWithEmailAndServerMessage() async throws {
        let model = authModel(.signup, body: #"{"success":true,"data":{"emailVerificationRequired":true,"token":"must-not-authenticate","user":{"id":"u","email":"a@example.test"},"message":"Check your email to verify your account."}}"#)
        defer { clearAuthFixture() }
        validSignup(model)
        await model.submit(authenticate: { _ in Issue.record("Verification must precede authentication") })
        #expect(model.screen == .login)
        #expect(model.email == "avery@example.test")
        #expect(model.password.isEmpty && model.confirmPassword.isEmpty && model.firstName.isEmpty && model.lastName.isEmpty)
        #expect(model.success == "Check your email to verify your account.")
        #expect(SessionStorage.getAccessToken() == nil)
        let request = try #require(MockURLProtocol.requests.first)
        let data = try #require(request.httpBody)
        let payload = try #require(JSONSerialization.jsonObject(with: data) as? [String: String])
        #expect(payload["firstName"] == "Avery" && payload["lastName"] == "Notary" && payload["email"] == "avery@example.test")
        model.navigate(.signup)
        #expect(model.success.isEmpty && model.error.isEmpty)
    }

    @Test func duplicateEmailUsesWebMessageForHTTPAndSuccessfulErrorPayloads() async {
        for (status, body) in [
            (409, #"{"message":"Conflict."}"#),
            (400, #"{"error":{"code":"USER_ALREADY_EXISTS"}}"#),
            (200, #"{"success":true,"data":{"code":"DUPLICATE_EMAIL"}}"#),
            (200, #"{"message":"Email already in use"}"#)
        ] {
            let model = authModel(.signup, status: status, body: body)
            defer { clearAuthFixture() }
            validSignup(model)
            await model.submit(authenticate: { _ in Issue.record("Duplicate must not authenticate") })
            #expect(model.error == AuthCopy.duplicateEmail)
            #expect(model.screen == .signup && model.success.isEmpty)
            #expect(model.password == "StrongPass12!")
        }
    }

    @Test func login401PreservesInvalidCredentialMessageAndMissingSessionCannotAuthenticate() async {
        for (status, body, message) in [
            (401, #"{"error":{"message":"Invalid email or password."}}"#, "Invalid email or password."),
            (403, #"{"message":"Please verify your email before signing in."}"#, "Please verify your email before signing in."),
            (429, #"{"message":"Too many attempts. Please try again later."}"#, "Too many attempts. Please try again later."),
            (200, #"{"token":"access","refreshToken":"refresh"}"#, "Login response was missing session data."),
            (200, #"{"user":{"id":"u","email":"a@example.test"}}"#, "Login response was missing session data.")
        ] {
            let model = authModel(status: status, body: body)
            defer { clearAuthFixture() }
            model.email = " a@example.test "; model.password = "secret"
            await model.submit(authenticate: { _ in Issue.record("Invalid response must not authenticate") })
            #expect(model.error == message)
            #expect(model.screen == .login && !model.isSubmitting)
            #expect(SessionStorage.getAccessToken() == nil)
        }
    }

    @Test func authenticatedSignupAndLoginClearFormAndCompleteExactlyOnce() async {
        for screen in [AuthScreen.signup, .login] {
            let model = authModel(screen, body: #"{"success":true,"data":{"accessToken":"access","refreshToken":"refresh","user":{"id":"u","firstName":"Avery","email":"avery@example.test"}}}"#)
            defer { clearAuthFixture() }
            validSignup(model)
            var completions = 0
            await model.submit(authenticate: { response in
                completions += 1
                #expect(response.user?.id == "u" && response.token == "access")
                #expect(response.refreshToken == "refresh")
                #expect(model.isSubmitting)
                await model.submit(authenticate: { _ in Issue.record("Duplicate request") })
            })
            #expect(completions == 1 && MockURLProtocol.requests.count == 1)
            #expect(model.email.isEmpty && model.password.isEmpty && model.success.isEmpty && !model.isSubmitting)
        }
    }

    @Test func forgotPasswordValidatesEmailAndStaysOnRecoveryWithExactSuccessCopy() async {
        let model = authModel(.forgot)
        defer { clearAuthFixture() }
        model.email = "not-an-email"
        await model.submit(authenticate: { _ in })
        #expect(model.error == "Please enter a valid email address.")
        #expect(MockURLProtocol.requests.isEmpty)
        model.email = " a@example.test "
        await model.submit(authenticate: { _ in })
        #expect(model.success == AuthCopy.resetSent && model.email.isEmpty && model.screen == .forgot)
        model.navigate(.login)
        #expect(model.success.isEmpty && model.error.isEmpty)
    }

    @Test func resetPasswordSendsNewPasswordAndReturnsToLoginWithPersistentConfirmation() async throws {
        let model = authModel(.reset, token: "one-time-token")
        defer { clearAuthFixture() }
        model.password = "StrongPass12!"; model.confirmPassword = model.password
        var resets = 0
        await model.submit(authenticate: { _ in Issue.record("Reset must not log in") }, passwordReset: { resets += 1 })
        #expect(resets == 1 && model.screen == .login && model.token.isEmpty)
        #expect(model.success == AuthCopy.resetComplete && model.password.isEmpty && model.confirmPassword.isEmpty)
        let request = try #require(MockURLProtocol.requests.first)
        let data = try #require(request.httpBody)
        let payload = try #require(JSONSerialization.jsonObject(with: data) as? [String: String])
        #expect(payload == ["token": "one-time-token", "newPassword": "StrongPass12!"])
        await model.submit(authenticate: { _ in })
        #expect(model.success.isEmpty && model.error == "Please enter your email.")
    }

    @Test func missingOrRejectedResetLinkStaysOnResetAndPreservesDraft() async {
        let missing = authModel(.reset)
        defer { clearAuthFixture() }
        #expect(missing.error == AuthCopy.missingResetToken)
        await missing.submit(authenticate: { _ in })
        #expect(MockURLProtocol.requests.isEmpty)
        let expired = authModel(.reset, token: "expired", status: 400, body: #"{"message":"Reset link has expired."}"#)
        expired.password = "StrongPass12!"; expired.confirmPassword = expired.password
        await expired.submit(authenticate: { _ in })
        #expect(expired.screen == .reset && expired.error == "Reset link has expired.")
        #expect(expired.password == "StrongPass12!" && expired.token == "expired")
    }

    @Test func verificationDistinguishesSuccessInvalidAndServerErrorsWithoutAutomaticLogin() async {
        for (status, expected) in [(200, VerificationStatus.success), (400, .invalid), (401, .invalid), (503, .error)] {
            let model = authModel(.verification, token: "verification-token", status: status)
            defer { clearAuthFixture() }
            await model.verify()
            #expect(model.verification == expected && model.screen == .verification && !model.isSubmitting)
            if expected != .error {
                await model.verify()
                #expect(MockURLProtocol.requests.count == 1, "Successful and invalid one-time links must not be consumed twice")
            }
            model.navigate(.login)
            #expect(model.screen == .login && model.error.isEmpty && model.success.isEmpty)
        }
        let missing = authModel(.verification)
        defer { clearAuthFixture() }
        await missing.verify()
        #expect(missing.verification == .invalid && MockURLProtocol.requests.isEmpty)
    }

    @Test func verificationNetworkFailureCanBeRetried() async {
        let model = authModel(.verification, token: "verification-token")
        defer { clearAuthFixture() }
        MockURLProtocol.requestHandler = { _ in throw URLError(.notConnectedToInternet) }
        await model.verify()
        #expect(model.verification == .error)
        MockURLProtocol.requestHandler = { MockURLProtocol.jsonResponse(for: $0, body: "{}") }
        await model.verify()
        #expect(model.verification == .success)
    }

    @Test func reopeningPendingVerificationReusesTheOneTimeTokenRequest() async {
        let model = authModel(.verification, token: "one-time-token")
        defer { clearAuthFixture() }
        var first: Task<Void, Never>?
        let signalLock = NSLock()
        var signal: CheckedContinuation<Void, Never>?
        await withCheckedContinuation { (started: CheckedContinuation<Void, Never>) in
            signal = started
            MockURLProtocol.requestHandler = { request in
                let pending = signalLock.withLock {
                    let pending = signal
                    signal = nil
                    return pending
                }
                pending?.resume()
                // Hold the URLProtocol response on its background callback long
                // enough to reopen the link while the first request is pending.
                Thread.sleep(forTimeInterval: 0.05)
                return MockURLProtocol.jsonResponse(for: request, body: "{}")
            }
            first = Task { await model.verify() }
        }
        model.navigate(.verification, token: "one-time-token")
        let second = Task { await model.verify() }
        await first?.value
        await second.value
        #expect(model.verification == .success)
        #expect(MockURLProtocol.requests.count == 1)
    }

    @Test func authLinksUseExactRoutesSupportResetFragmentsAndValidateDestinations() throws {
        for (url, screen, token) in [
            ("https://notaryledger.org/verify-email?token=valid", AuthScreen.verification, "valid"),
            ("https://notaryledger.org/verify-email", .verification, ""),
            ("https://notaryledger.org/reset-password#token=fragment", .reset, "fragment"),
            ("https://notaryledger.org/reset-password#/?resetToken=fragment", .reset, "fragment"),
            ("notaryledger://reset-password?resetToken=custom", .reset, "custom")
        ] {
            let link = try #require(AuthLink(url: URL(string: url)!))
            #expect(link.screen == screen && link.token == token)
        }
        #expect(AuthLink(url: URL(string: "https://notaryledger.org/unrelated-reset-page?token=wrong")!) == nil)
        #expect(AuthLink(url: URL(string: "https://notaryledger.org/login?next=https://example.test")!)?.destination == nil)
        #expect(AuthLink(url: URL(string: "https://notaryledger.org/signup?next=billing")!)?.destination == .billing)
        #expect(AuthLink(url: URL(string: "https://notaryledger.org/app/orders")!)?.destination == .signings)
    }

    @Test func authenticationLandsOnIntendedScreenAndLogoutReturnsToCleanLogin() async throws {
        MockURLProtocol.requestHandler = { request in
            let body = request.url?.path == "/api/config/maintenance" ? #"{"enabled":false}"# : "[]"
            return MockURLProtocol.jsonResponse(for: request, body: body)
        }
        defer { clearAuthFixture() }
        let service = APIService(baseURL: "https://auth.example.test", session: MockURLProtocol.session())
        let state = AppState(api: service)
        state.openURL(URL(string: "https://notaryledger.org/signup?next=billing")!)
        #expect(state.auth.screen == .signup)
        let response = AuthResponse(token: "fixture-token", user: AuthUser(id: "u", fullName: "Avery", email: "a@example.test"))
        await state.didAuthenticate(response)
        if case .app = state.route {} else { Issue.record("Expected authenticated app") }
        #expect(state.selectedSection == .billing)
        state.auth.password = "Must be cleared"
        state.signOutLocally()
        #expect(state.auth.screen == .login && state.auth.password.isEmpty)
        if case .auth = state.route {} else { Issue.record("Expected login") }
        await state.didAuthenticate(response)
        #expect(state.selectedSection == .dashboard)
        state.signOutLocally()
        state.openURL(URL(string: "https://notaryledger.org/login?next=admin-audit-logs")!)
        await state.didAuthenticate(response)
        #expect(state.selectedSection == .dashboard, "Non-admin must not land on admin screens")
    }

    @Test func expiredSessionOnAnyProtectedRequestReturnsToLoginAndRemembersDestination() async throws {
        SessionStorage.clearSession()
        MockURLProtocol.requestHandler = { request in
            if request.url?.path == "/api/config/maintenance" {
                return MockURLProtocol.jsonResponse(for: request, body: #"{"enabled":false}"#)
            }
            return MockURLProtocol.jsonResponse(for: request, statusCode: 401, body: #"{"message":"Expired."}"#)
        }
        defer { clearAuthFixture() }
        let service = APIService(baseURL: "https://auth.example.test", session: MockURLProtocol.session())
        let user = AuthUser(id: "u", fullName: "Avery", email: "a@example.test")
        let response = AuthResponse(token: "fixture-token", user: user)
        SessionStorage.saveSession(response)
        let state = AppState(api: service)
        state.route = .app; state.currentUser = user; state.selectedSection = .billing
        do { _ = try await service.fetchBillingStatus(); Issue.record("Expected expired session") }
        catch APIError.unauthorized { }
        #expect(state.auth.screen == .login)
        #expect(state.auth.error == "Your session has expired. Please sign in again.")
        if case .auth = state.route {} else { Issue.record("Expected login") }
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(for: request, body: request.url?.path == "/api/config/maintenance" ? #"{"enabled":false}"# : "[]")
        }
        await state.didAuthenticate(response)
        #expect(state.selectedSection == .billing)
    }

    @Test func protectedLinkWaitsForSessionRestorationAndHonorsDestination() async throws {
        SessionStorage.clearSession()
        var response = AuthResponse(token: "old-access", user: AuthUser(id: "u", fullName: "Avery", email: "a@example.test"))
        response.refreshToken = "old-refresh"
        SessionStorage.saveSession(response)
        MockURLProtocol.requestHandler = { request in
            let body: String
            switch request.url?.path {
            case "/api/config/maintenance": body = #"{"enabled":false}"#
            case "/api/auth/refresh": body = #"{"accessToken":"new-access","refreshToken":"new-refresh"}"#
            case "/api/auth/me": body = #"{"id":"u","fullName":"Avery","email":"a@example.test"}"#
            default: body = "[]"
            }
            return MockURLProtocol.jsonResponse(for: request, body: body)
        }
        defer { clearAuthFixture() }
        let service = APIService(baseURL: "https://auth.example.test", session: MockURLProtocol.session())
        let state = AppState(api: service)
        state.openURL(URL(string: "https://notaryledger.org/app/invoices")!)
        #expect(state.isRestoringSession)
        await state.boot()
        #expect(!state.isRestoringSession && state.selectedSection == .invoices)
        if case .app = state.route {} else { Issue.record("Expected restored session") }
    }
}

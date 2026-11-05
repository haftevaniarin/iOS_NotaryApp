import Foundation
import Combine

// Copy and transitions follow App.jsx's authentication handlers.
enum AuthCopy {
    static let passwordRequirements = "Password must be 12-128 characters, cannot be only spaces, and must include at least 3 of these: lowercase letter, uppercase letter, number, and symbol."
    static let passwordHint = "Use 12-128 characters, not only spaces, and include at least 3 of these: lowercase letter, uppercase letter, number, and symbol."
    static let duplicateEmail = "An account with this email already exists. Please sign in or use a different email address."
    static let verifyAccount = "Check your email to verify your account, then sign in."
    static let resetSent = "If an account exists for that email, a password reset link has been sent."
    static let resetComplete = "Your password has been reset. Sign in with your new password."
    static let missingResetToken = "This reset link is missing a token. Request a new password reset email."
}

enum AuthScreen: Equatable { case login, signup, forgot, reset, verification }

enum VerificationStatus: Equatable {
    case loading, success, invalid, error
    var title: String {
        switch self {
        case .loading: "Verifying email"
        case .success: "Email verified successfully"
        case .invalid: "This verification link is invalid or expired."
        case .error: "We could not verify your email right now."
        }
    }
    var message: String {
        switch self {
        case .loading: "Checking your verification link."
        case .success: "Your email address is verified. Sign in to continue."
        case .invalid: "Request a new verification email from sign in or create a new account."
        case .error: "There was a network or server problem. Try the verification link again later."
        }
    }
}

struct AuthLink: Equatable {
    let screen: AuthScreen?
    let token: String
    let destination: AppSection?
    init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let path = url.scheme == "notaryledger" ? "/" + (url.host ?? "") + url.path : url.path
        func query(_ name: String) -> String? { components.queryItems?.first { $0.name == name }?.value?.nilIfEmpty }
        let destinations: [String: AppSection] = ["dashboard": .dashboard, "orders": .signings, "signings": .signings, "invoices": .invoices, "expenses": .expenses, "customers": .customers, "reports": .taxSummary, "taxSummary": .taxSummary, "tax-summary": .taxSummary, "billing": .billing, "profile": .profile, "businessCard": .businessCard, "business-card": .businessCard, "rescission": .rescission, "rescission-calculator": .rescission, "adminAudit": .adminAudit, "admin-audit-logs": .adminAudit]
        token = query("token") ?? query("resetToken") ?? query("verificationToken") ?? {
            let fragment = components.fragment ?? ""
            let fragmentQuery = fragment.contains("?") ? String(fragment.split(separator: "?", maxSplits: 1).last ?? "") : fragment
            let items = URLComponents(string: "https://notaryledger.org/?" + fragmentQuery)?.queryItems
            return items?.first { $0.name == "token" || $0.name == "resetToken" }?.value ?? ""
        }()
        let pathKey = path.hasPrefix("/app/") ? String(path.dropFirst(5)) : String(path.dropFirst())
        let pathDestination: AppSection? = path == "/app" ? .dashboard : pathKey == "admin/audit-logs" ? .adminAudit : destinations[pathKey]
        destination = query("next").flatMap { destinations[$0] } ?? pathDestination
        switch path {
        case "/login", "/": screen = .login
        case "/signup": screen = .signup
        case "/forgot-password": screen = .forgot
        case "/reset-password": screen = .reset
        case "/verify-email": screen = .verification
        default:
            guard pathDestination != nil else { return nil }
            screen = nil
        }
    }
}

@MainActor
final class AuthFlowModel: ObservableObject {
    @Published private(set) var screen: AuthScreen
    @Published var firstName = ""
    @Published var lastName = ""
    @Published var email = ""
    @Published var password = ""
    @Published var confirmPassword = ""
    @Published private(set) var error = ""
    @Published private(set) var success = ""
    @Published private(set) var fieldErrors: [String: String] = [:]
    @Published private(set) var isSubmitting = false
    @Published private(set) var verification: VerificationStatus = .loading
    @Published private(set) var token: String
    private let api: APIService
    private var revision = 0
    private var verificationResults: [String: VerificationStatus] = [:]
    private var verificationRequests: [String: Task<Void, Error>] = [:]
    // No actor-bound cleanup; avoid the iOS 26.1 isolated-deinit runtime bug.
    nonisolated deinit {}

    init(screen: AuthScreen = .login, token: String = "", api: APIService? = nil) {
        self.screen = screen; self.token = token; self.api = api ?? APIService.shared
        if screen == .reset && token.isEmpty { error = AuthCopy.missingResetToken }
        if screen == .verification && token.isEmpty { verification = .invalid }
    }
    var verificationTaskID: Int? { screen == .verification ? revision : nil }
    func navigate(_ screen: AuthScreen, token: String = "") {
        revision += 1
        self.screen = screen; self.token = token
        error = screen == .reset && token.isEmpty ? AuthCopy.missingResetToken : ""
        success = ""; fieldErrors = [:]; isSubmitting = false
        verification = token.isEmpty ? .invalid : .loading
    }
    func reset() {
        navigate(.login)
        clearForm()
    }
    func showError(_ message: String) { error = message; success = "" }
    func clearFieldError(_ field: String) { fieldErrors[field] = nil }
    private func clearForm(keepingEmail: Bool = false) {
        firstName = ""; lastName = ""; password = ""; confirmPassword = ""
        email = keepingEmail ? email.trimmingCharacters(in: .whitespacesAndNewlines) : ""
    }
    private func validate() -> Bool {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if screen == .signup {
            for (field, name, value) in [("firstName", "first", firstName), ("lastName", "last", lastName)] {
                let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if value.isEmpty { fieldErrors[field] = "Please enter your \(name) name." }
                if value.utf16.count > 100 { fieldErrors[field] = "\(name.capitalized) name must be 100 characters or less." }
            }
            if !fieldErrors.isEmpty { return false }
        }
        if screen == .reset && token.isEmpty { error = AuthCopy.missingResetToken; return false }
        if screen != .reset {
            if cleanEmail.isEmpty { error = "Please enter your email."; return false }
            if screen != .login && (!email.contains("@") || !email.contains(".")) {
                error = "Please enter a valid email address."; return false
            }
        }
        if screen == .login && password.isEmpty { error = "Please enter your password."; return false }
        if screen == .signup || screen == .reset {
            if let message = PasswordValidation.message(for: password) { error = message; return false }
            if password != confirmPassword { error = "Passwords do not match."; return false }
        }
        return true
    }
    func submit(authenticate: (AuthResponse) async -> Void, passwordReset: () -> Void = {}) async {
        guard !isSubmitting, screen != .verification else { return }
        error = ""; success = ""; fieldErrors = [:]
        guard validate() else { return }
        isSubmitting = true
        let started = revision
        let submittedScreen = screen
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        defer { if revision == started { isSubmitting = false } }
        do {
            switch submittedScreen {
            case .login:
                let response = try await api.login(email: cleanEmail, password: password)
                guard revision == started else { return }
                await authenticate(response)
                clearForm()
            case .signup:
                let result = try await api.register(firstName: firstName.trimmingCharacters(in: .whitespacesAndNewlines), lastName: lastName.trimmingCharacters(in: .whitespacesAndNewlines), email: cleanEmail, password: password)
                guard revision == started else { return }
                switch result {
                case .authenticated(let response):
                    await authenticate(response)
                    clearForm()
                case .verificationRequired(let message):
                    screen = .login
                    clearForm(keepingEmail: true)
                    success = message
                }
            case .forgot:
                try await api.forgotPassword(email: cleanEmail)
                guard revision == started else { return }
                success = AuthCopy.resetSent
                clearForm()
            case .reset:
                try await api.resetPassword(token: token, password: password)
                guard revision == started else { return }
                passwordReset()
                screen = .login; token = ""
                clearForm()
                success = AuthCopy.resetComplete
            case .verification: break
            }
        } catch {
            guard revision == started else { return }
            self.error = error.localizedDescription
        }
    }
    func verify() async {
        guard screen == .verification else { return }
        guard !token.isEmpty else { verification = .invalid; return }
        if let cached = verificationResults[token] { verification = cached; return }
        guard !isSubmitting else { return }
        isSubmitting = true; verification = .loading
        let started = revision
        let submittedToken = token
        let request = verificationRequests[submittedToken] ?? Task { [api] in
            try await api.verifyEmail(token: submittedToken)
        }
        verificationRequests[submittedToken] = request
        defer { if revision == started { isSubmitting = false } }
        do {
            try await request.value
            verificationRequests[submittedToken] = nil
            verificationResults[submittedToken] = .success
            if revision == started { verification = .success }
        } catch {
            verificationRequests[submittedToken] = nil
            let status: VerificationStatus
            if case APIError.httpError(let code, _) = error, code < 500 { status = .invalid }
            else if case APIError.unauthorized = error { status = .invalid }
            else { status = .error }
            if status == .invalid { verificationResults[submittedToken] = status }
            if revision == started { verification = status }
        }
    }
}

import SwiftUI

struct AuthFlowView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var model: AuthFlowModel

    init(model: AuthFlowModel) { _model = StateObject(wrappedValue: model) }
    init(screen: AuthScreen, token: String = "") {
        _model = StateObject(wrappedValue: AuthFlowModel(screen: screen, token: token))
    }
    private var title: String {
        switch model.screen {
        case .login: "Welcome back"
        case .signup: "Set up your desk"
        case .forgot: "Recover your password"
        case .reset: "Reset your password"
        case .verification: model.verification.title
        }
    }
    private var subtitle: String {
        switch model.screen {
        case .login: "Sign in to your signing desk."
        case .signup: "Track signings, fees, and clients in one place."
        case .forgot: "Enter your email and we will send a reset link."
        case .reset: "Choose a new password for your account."
        case .verification: model.verification.message
        }
    }
    var body: some View {
        ScrollViewReader { proxy in
            AuthShell(title: title, subtitle: "SIGNING AGENT DESK") {
                VStack(alignment: .leading, spacing: NLSpacing.md) {
                    Text(subtitle).font(NLTypography.body).foregroundColor(NLColor.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if model.screen == .verification {
                        verificationActions
                    } else {
                        if model.screen == .login || model.screen == .signup {
                            HStack {
                                Button("Login") { model.navigate(.login) }
                                    .buttonStyle(SecondaryButtonStyle())
                                Button("Sign Up") { model.navigate(.signup) }
                                    .buttonStyle(SecondaryButtonStyle())
                                    .accessibilityIdentifier("Create account")
                            }.disabled(model.isSubmitting)
                        }
                        ErrorBanner(message: model.error)
                        BannerView(kind: .success, message: model.success)
                        if model.screen == .signup {
                            nameField("First name", text: $model.firstName, key: "firstName")
                            nameField("Last name", text: $model.lastName, key: "lastName")
                        }
                        if model.screen != .reset {
                            NLTextField(title: "Email", text: $model.email, keyboardType: .emailAddress)
                                .textContentType(.username)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                        }
                        if model.screen != .forgot {
                            AuthPasswordField(title: model.screen == .reset ? "New password" : "Password", text: $model.password,
                                              newPassword: model.screen != .login)
                            if model.screen == .signup || model.screen == .reset {
                                Text(AuthCopy.passwordHint).font(NLTypography.caption).foregroundColor(NLColor.muted)
                                AuthPasswordField(title: model.screen == .reset ? "Confirm new password" : "Confirm password",
                                                  text: $model.confirmPassword, newPassword: false)
                            }
                        }
                        if model.screen == .login {
                            Button("Forgot password?") { model.navigate(.forgot) }
                                .accessibilityIdentifier("Forgot password")
                        }
                        Button(buttonTitle) {
                            Task {
                                await model.submit(authenticate: { await appState.didAuthenticate($0) },
                                                   passwordReset: { appState.signOutLocally() })
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier(model.screen == .login ? "Log In" : model.screen == .signup ? "Create Account" : model.screen == .forgot ? "Send Reset Link" : "Reset Password")
                        .disabled(model.isSubmitting || (model.screen == .reset && model.token.isEmpty))
                        if model.screen == .forgot || model.screen == .reset {
                            Button("Back to sign in") { model.navigate(.login) }.disabled(model.isSubmitting)
                        }
                    }
                    HStack {
                        NavigationLink("Terms & Conditions") {
                            LegalDocumentView(kind: .terms, onSignIn: { model.navigate(.login) })
                        }
                        Spacer(minLength: NLSpacing.sm)
                        NavigationLink("Privacy Policy") {
                            LegalDocumentView(kind: .privacy, onSignIn: { model.navigate(.login) })
                        }
                    }.font(NLTypography.caption).foregroundColor(NLColor.muted)
                }
                .disabled(model.isSubmitting && model.screen != .verification)
            }
            .task(id: model.verificationTaskID) { await model.verify() }
            .onChange(of: model.error) { _, message in
                if !message.isEmpty { showHeading(proxy) }
            }
            .onChange(of: model.success) { _, message in
                if !message.isEmpty { showHeading(proxy) }
            }
            .onChange(of: model.fieldErrors) { _, errors in
                if !errors.isEmpty { showHeading(proxy) }
            }
            .onChange(of: model.screen) { _, _ in showHeading(proxy) }
        }
    }
    private func showHeading(_ proxy: ScrollViewProxy) {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        withAnimation { proxy.scrollTo("authHeading", anchor: .top) }
    }
    private var buttonTitle: String {
        switch model.screen {
        case .login: model.isSubmitting ? "Signing in..." : "Sign in"
        case .signup: model.isSubmitting ? "Creating account..." : "Create account"
        case .forgot: model.isSubmitting ? "Sending reset link..." : "Send reset link"
        case .reset: model.isSubmitting ? "Resetting password..." : "Reset password"
        case .verification: "Go to sign in"
        }
    }
    @ViewBuilder private var verificationActions: some View {
        if model.verification == .loading {
            ProgressView().accessibilityLabel("Verifying email")
        } else {
            Button("Go to sign in") { model.navigate(.login) }.buttonStyle(PrimaryButtonStyle())
            if model.verification != .success {
                Button("Create account") { model.navigate(.signup) }.buttonStyle(SecondaryButtonStyle())
            }
        }
    }
    private func nameField(_ title: String, text: Binding<String>, key: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            NLTextField(title: title, text: text)
                .textContentType(key == "firstName" ? .givenName : .familyName)
                .onChange(of: text.wrappedValue) { _, _ in model.clearFieldError(key) }
            if let error = model.fieldErrors[key] {
                Text(error).font(NLTypography.caption).foregroundColor(NLColor.danger)
                    .accessibilityIdentifier("\(key) error")
            }
        }
    }
}

private struct AuthPasswordField: View {
    let title: String
    @Binding var text: String
    let newPassword: Bool
    @State private var isVisible = false
    @ScaledMetric private var inputHeight: CGFloat = 22
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel(text: title)
            HStack {
                AuthPasswordInput(title: title, text: $text, newPassword: newPassword, isVisible: isVisible)
                    .frame(height: inputHeight)
                Button { isVisible.toggle() } label: {
                    Image(systemName: isVisible ? "eye.slash" : "eye")
                }
                .accessibilityLabel((isVisible ? "Hide " : "Show ") + title.lowercased())
            }
            .font(NLTypography.input).padding(12).frame(minHeight: 42)
            .background(Color(red: 0.992, green: 0.988, blue: 0.973))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(NLColor.line, lineWidth: 1))
        }
    }
}

// Keep one native input alive when text changes or visibility is toggled.
// Replacing SecureField with TextField can interrupt password entry and AutoFill.
private struct AuthPasswordInput: UIViewRepresentable {
    let title: String
    @Binding var text: String
    let newPassword: Bool
    let isVisible: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.font = UIFontMetrics.default.scaledFont(for: UIFont(name: "NLBody-Regular", size: 14) ?? .systemFont(ofSize: 14))
        field.adjustsFontForContentSizeCategory = true
        field.textColor = UIColor(NLColor.ink)
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.returnKeyType = .done
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        return field
    }
    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.owner = self
        if field.isEnabled != context.environment.isEnabled { field.isEnabled = context.environment.isEnabled }
        if field.placeholder != title { field.placeholder = title }
        field.accessibilityIdentifier = title
        field.accessibilityLabel = title
        let contentType: UITextContentType = {
            #if DEBUG
            // Isolate scripted input from the simulator's strong-password UI.
            if ProcessInfo.processInfo.arguments.contains("--auth-fixtures") { return .oneTimeCode }
            #endif
            return newPassword ? .newPassword : .password
        }()
        if context.coordinator.contentType != contentType {
            context.coordinator.contentType = contentType
            field.textContentType = contentType
        }
        if field.isSecureTextEntry == isVisible {
            let value = field.text
            field.isSecureTextEntry = !isVisible
            field.text = value
        }
        if field.text != text { field.text = text }
    }
    final class Coordinator: NSObject, UITextFieldDelegate {
        var owner: AuthPasswordInput
        var contentType: UITextContentType?
        nonisolated deinit {}
        init(_ owner: AuthPasswordInput) { self.owner = owner }
        @objc func changed(_ field: UITextField) { owner.text = field.text ?? "" }
        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
    }
}

// Keep the existing entry points available to previews and callers.
struct LoginView: View {
    @EnvironmentObject private var appState: AppState
    var body: some View { AuthFlowView(model: appState.auth) }
}
struct SignUpView: View { var body: some View { AuthFlowView(screen: .signup) } }
struct ForgotPasswordView: View { var body: some View { AuthFlowView(screen: .forgot) } }
struct ResetPasswordView: View {
    let token: String
    var body: some View { AuthFlowView(screen: .reset, token: token) }
}
struct VerificationView: View {
    let token: String
    var body: some View { AuthFlowView(screen: .verification, token: token) }
}

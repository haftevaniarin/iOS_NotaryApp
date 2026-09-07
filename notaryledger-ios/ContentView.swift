import SwiftUI

struct ContentView: View {
    @StateObject private var appState = AppState()
    @State private var verificationSheet: TokenSheet?
    @State private var resetSheet: TokenSheet?

    var body: some View {
        Group {
            switch appState.route {
            case .auth:
                NavigationStack {
                    LoginView()
                }
            case .app:
                MainTabView()
            case .maintenance(let status):
                MaintenanceView(status: status)
            }
        }
        .environmentObject(appState)
        .task {
            await appState.boot()
        }
        .sheet(item: $verificationSheet) { sheet in
            VerificationView(token: sheet.token)
                .environmentObject(appState)
        }
        .sheet(item: $resetSheet) { sheet in
            NavigationStack {
                ResetPasswordView(token: sheet.token)
            }
        }
        .onOpenURL { url in
            if let token = url.queryItem(named: "verificationToken") ?? url.queryItem(named: "token"),
               url.absoluteString.contains("verify") {
                verificationSheet = TokenSheet(token: token)
            } else if let token = url.queryItem(named: "resetToken") ?? url.queryItem(named: "token"),
                      url.absoluteString.contains("reset") {
                resetSheet = TokenSheet(token: token)
            }
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            NavigationStack {
                DashboardView()
            }
            .tabItem {
                Label("Dashboard", systemImage: "chart.bar.doc.horizontal")
            }

            NavigationStack {
                SigningsView()
            }
            .tabItem {
                Label("Signings", systemImage: "doc.text")
            }

            NavigationStack {
                ExpensesView()
            }
            .tabItem {
                Label("Expenses", systemImage: "creditcard")
            }

            NavigationStack {
                CustomersView()
            }
            .tabItem {
                Label("Customers", systemImage: "person.2")
            }

            NavigationStack {
                MoreView()
            }
            .tabItem {
                Label("More", systemImage: "ellipsis.circle")
            }
        }
        .tint(NLColor.navy)
    }
}

struct AuthShell<Content: View>: View {
    let title: String
    let subtitle: String
    let content: Content

    init(title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        ZStack {
            ParchmentBackground()
            ScrollView {
                VStack(spacing: NLSpacing.xl) {
                    VStack(spacing: NLSpacing.sm) {
                        Image(systemName: "seal")
                            .font(.system(size: 54))
                            .foregroundColor(NLColor.brass)
                        Text("Notary Ledger")
                            .font(.largeTitle.bold())
                            .foregroundColor(NLColor.navy)
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundColor(NLColor.muted)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 30)

                    VStack(alignment: .leading, spacing: NLSpacing.lg) {
                        Text(title)
                            .font(.title3.weight(.semibold))
                            .foregroundColor(NLColor.ink)
                        content
                    }
                    .nlPanel()
                }
                .padding(NLSpacing.lg)
            }
        }
    }
}

struct LoginView: View {
    @EnvironmentObject private var appState: AppState
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage = ""
    @State private var isSubmitting = false

    var body: some View {
        AuthShell(title: "Log In", subtitle: "Manage signings, invoices, expenses, and tax records.") {
            VStack(spacing: NLSpacing.md) {
                TextField("Email", text: $email)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                    .textFieldStyle(.roundedBorder)

                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .textFieldStyle(.roundedBorder)

                ErrorBanner(message: errorMessage)

                Button {
                    Task { await login() }
                } label: {
                    if isSubmitting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Log In")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isSubmitting)

                HStack {
                    NavigationLink("Create account") {
                        SignUpView()
                    }
                    Spacer()
                    NavigationLink("Forgot password") {
                        ForgotPasswordView()
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(NLColor.navy)
            }
        }
    }

    private func login() async {
        errorMessage = ""
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanEmail.isEmpty else {
            errorMessage = "Enter your email address."
            return
        }
        guard !password.isEmpty else {
            errorMessage = "Enter your password."
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let response = try await APIService.shared.login(email: cleanEmail, password: password)
            await appState.didAuthenticate(response)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct SignUpView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var errorMessage = ""
    @State private var isSubmitting = false

    var body: some View {
        AuthShell(title: "Create Account", subtitle: "Set up your secure notary bookkeeping workspace.") {
            VStack(spacing: NLSpacing.md) {
                HStack(spacing: NLSpacing.md) {
                    TextField("First name", text: $firstName)
                        .textFieldStyle(.roundedBorder)
                    TextField("Last name", text: $lastName)
                        .textFieldStyle(.roundedBorder)
                }
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                    .textFieldStyle(.roundedBorder)
                SecureField("Password", text: $password)
                    .textContentType(.newPassword)
                    .textFieldStyle(.roundedBorder)
                SecureField("Confirm password", text: $confirmPassword)
                    .textContentType(.newPassword)
                    .textFieldStyle(.roundedBorder)

                ErrorBanner(message: errorMessage)

                Button {
                    Task { await signup() }
                } label: {
                    Text(isSubmitting ? "Creating..." : "Create Account")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isSubmitting)

                Button("Back to login") {
                    dismiss()
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func signup() async {
        errorMessage = ""
        let fullName = [firstName, lastName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !fullName.isEmpty else {
            errorMessage = "Enter your name."
            return
        }
        guard email.contains("@") else {
            errorMessage = "Enter a valid email address."
            return
        }
        if let passwordMessage = PasswordValidation.message(for: password) {
            errorMessage = passwordMessage
            return
        }
        guard password == confirmPassword else {
            errorMessage = "Passwords do not match."
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let response = try await APIService.shared.signup(fullName: fullName, email: email, password: password)
            await appState.didAuthenticate(response)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ForgotPasswordView: View {
    @State private var email = ""
    @State private var message = ""
    @State private var errorMessage = ""
    @State private var isSubmitting = false

    var body: some View {
        ZStack {
            ParchmentBackground()
            Form {
                Section("Account Email") {
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                if !message.isEmpty {
                    Section {
                        Text(message)
                            .foregroundColor(NLColor.navy)
                    }
                }
                if !errorMessage.isEmpty {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    }
                }

                Section {
                    Button("Send Reset Link") {
                        Task { await submit() }
                    }
                    .disabled(isSubmitting)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Forgot Password")
    }

    private func submit() async {
        errorMessage = ""
        message = ""
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanEmail.isEmpty else {
            errorMessage = "Enter your email address."
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await APIService.shared.forgotPassword(email: cleanEmail)
            message = "If an account exists, a reset link has been sent."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ResetPasswordView: View {
    @Environment(\.dismiss) private var dismiss
    let token: String
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var message = ""
    @State private var errorMessage = ""
    @State private var isSubmitting = false

    var body: some View {
        ZStack {
            ParchmentBackground()
            Form {
                Section("New Password") {
                    SecureField("Password", text: $password)
                    SecureField("Confirm password", text: $confirmPassword)
                }
                if !message.isEmpty {
                    Section { Text(message).foregroundColor(NLColor.navy) }
                }
                if !errorMessage.isEmpty {
                    Section { Text(errorMessage).foregroundColor(.red) }
                }
                Section {
                    Button("Reset Password") {
                        Task { await submit() }
                    }
                    .disabled(isSubmitting)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Reset Password")
    }

    private func submit() async {
        errorMessage = ""
        if let passwordMessage = PasswordValidation.message(for: password) {
            errorMessage = passwordMessage
            return
        }
        guard password == confirmPassword else {
            errorMessage = "Passwords do not match."
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await APIService.shared.resetPassword(token: token, password: password)
            message = "Your password has been reset."
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct VerificationView: View {
    @Environment(\.dismiss) private var dismiss
    let token: String
    @State private var state = "Verifying your email..."

    var body: some View {
        VStack(spacing: NLSpacing.lg) {
            Image(systemName: "envelope.badge.shield.half.filled")
                .font(.system(size: 44))
                .foregroundColor(NLColor.brass)
            Text(state)
                .font(.headline)
                .multilineTextAlignment(.center)
            Button("Done") {
                dismiss()
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding()
        .presentationDetents([.medium])
        .task {
            do {
                try await APIService.shared.verifyEmail(token: token)
                state = "Email verified."
            } catch {
                state = error.localizedDescription
            }
        }
    }
}

struct MaintenanceView: View {
    let status: MaintenanceStatus

    var body: some View {
        ZStack {
            ParchmentBackground()
            VStack(spacing: NLSpacing.lg) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 46))
                    .foregroundColor(NLColor.brass)
                Text(status.title ?? "Maintenance in Progress")
                    .font(.title2.bold())
                    .foregroundColor(NLColor.navy)
                Text(status.message ?? "Notary Ledger is temporarily unavailable. Please try again soon.")
                    .font(.body)
                    .foregroundColor(NLColor.muted)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .nlPanel()
            .padding()
        }
    }
}

struct MoreView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        List {
            NavigationLink {
                InvoicesView()
            } label: {
                Label("Invoices", systemImage: "doc.richtext")
            }

            NavigationLink {
                TaxSummaryView()
            } label: {
                Label("Tax Summary", systemImage: "sum")
            }

            NavigationLink {
                ProfileView()
            } label: {
                Label("Profile", systemImage: "person.crop.circle")
            }
        }
        .navigationTitle("More")
        .scrollContentBackground(.hidden)
        .background(ParchmentBackground())
    }
}

struct TokenSheet: Identifiable {
    let id = UUID()
    let token: String
}

private extension URL {
    func queryItem(named name: String) -> String? {
        URLComponents(url: self, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == name })?
            .value
    }
}

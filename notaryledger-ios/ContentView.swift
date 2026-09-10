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
                LedgerAppShell()
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

enum AppSection: String, CaseIterable, Identifiable {
    case dashboard
    case signings
    case rescission
    case invoices
    case expenses
    case customers
    case taxSummary
    case billing
    case profile
    case terms
    case privacy
    case adminAudit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .signings: "Signings"
        case .rescission: "Rescission Calculator"
        case .invoices: "Invoices"
        case .expenses: "Expenses"
        case .customers: "Customers"
        case .taxSummary: "Tax Summary"
        case .billing: "Billing"
        case .profile: "Profile"
        case .terms: "Terms & Conditions"
        case .privacy: "Privacy Policy"
        case .adminAudit: "Admin Audit Logs"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: "chart.bar.doc.horizontal"
        case .signings: "doc.text"
        case .rescission: "calendar.badge.clock"
        case .invoices: "doc.richtext"
        case .expenses: "creditcard"
        case .customers: "person.2"
        case .taxSummary: "sum"
        case .billing: "creditcard.and.123"
        case .profile: "person.crop.circle"
        case .terms: "doc.plaintext"
        case .privacy: "lock.shield"
        case .adminAudit: "checklist.checked"
        }
    }
}

struct LedgerAppShell: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedSection: AppSection = .dashboard
    @State private var isMenuOpen = false

    private var primarySections: [AppSection] {
        [.dashboard, .signings, .rescission, .invoices, .expenses, .customers, .taxSummary, .billing, .profile]
    }

    var body: some View {
        ZStack(alignment: .leading) {
            ParchmentBackground()

            VStack(spacing: 0) {
                LedgerTopBar(title: selectedSection.title) {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        isMenuOpen.toggle()
                    }
                }

                NavigationStack {
                    sectionView
                        .toolbar(.hidden, for: .navigationBar)
                }
            }

            if isMenuOpen {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            isMenuOpen = false
                        }
                    }

                LedgerSideMenu(
                    selectedSection: $selectedSection,
                    isMenuOpen: $isMenuOpen,
                    primarySections: primarySections
                )
                .transition(.move(edge: .leading))
            }
        }
    }

    @ViewBuilder
    private var sectionView: some View {
        switch selectedSection {
        case .dashboard:
            DashboardView()
        case .signings:
            SigningsView()
        case .rescission:
            RescissionCalculatorView()
        case .invoices:
            InvoicesView()
        case .expenses:
            ExpensesView()
        case .customers:
            CustomersView()
        case .taxSummary:
            TaxSummaryView()
        case .billing:
            BillingView()
        case .profile:
            ProfileView()
        case .terms:
            LegalDocumentView(kind: .terms)
        case .privacy:
            LegalDocumentView(kind: .privacy)
        case .adminAudit:
            AdminAuditLogsView()
        }
    }
}

struct LedgerTopBar: View {
    let title: String
    let onMenu: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: NLSpacing.md) {
                Button(action: onMenu) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 42, height: 42)
                        .foregroundColor(.white)
                }
                .accessibilityLabel("Open navigation menu")

                BrandLockup(compact: true)

                Spacer(minLength: 8)
            }
            .padding(.horizontal, NLSpacing.lg)
            .padding(.top, 6)
            .padding(.bottom, 10)

            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.88))
                Spacer()
            }
            .padding(.horizontal, NLSpacing.lg)
            .padding(.bottom, 10)
        }
        .background(NLColor.navy.ignoresSafeArea(edges: .top))
    }
}

struct LedgerSideMenu: View {
    @EnvironmentObject private var appState: AppState
    @Binding var selectedSection: AppSection
    @Binding var isMenuOpen: Bool
    let primarySections: [AppSection]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BrandLockup()
                .padding(.horizontal, NLSpacing.lg)
                .padding(.top, 20)
                .padding(.bottom, NLSpacing.lg)

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(primarySections) { section in
                        menuButton(for: section)
                    }

                    Divider()
                        .overlay(Color.white.opacity(0.18))
                        .padding(.vertical, NLSpacing.md)

                    menuButton(for: .terms)
                    menuButton(for: .privacy)

                    if appState.currentUser?.canAccessAdminAudit == true {
                        Divider()
                            .overlay(Color.white.opacity(0.18))
                            .padding(.vertical, NLSpacing.md)
                        menuButton(for: .adminAudit)
                    }
                }
                .padding(.horizontal, NLSpacing.md)
            }

            VStack(alignment: .leading, spacing: NLSpacing.md) {
                if let user = appState.currentUser {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(user.fullName.isEmpty ? "Notary Ledger user" : user.fullName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(user.email)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.70))
                            .lineLimit(1)
                    }
                }

                Button {
                    Task { await appState.signOut() }
                } label: {
                    Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                }
            }
            .padding(NLSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NLColor.navySoft.opacity(0.55))
        }
        .frame(width: 318)
        .frame(maxHeight: .infinity)
        .background(NLColor.navy.ignoresSafeArea())
    }

    private func menuButton(for section: AppSection) -> some View {
        Button {
            selectedSection = section
            withAnimation(.easeInOut(duration: 0.22)) {
                isMenuOpen = false
            }
        } label: {
            HStack(spacing: NLSpacing.md) {
                Image(systemName: section.systemImage)
                    .frame(width: 22)
                Text(section.title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundColor(selectedSection == section ? NLColor.navy : .white)
            .padding(.horizontal, NLSpacing.md)
            .padding(.vertical, 11)
            .background(selectedSection == section ? NLColor.parchment : Color.white.opacity(0.0001))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .accessibilityLabel(section.title)
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
                        NLSeal(size: 58)
                        Text("Notary Ledger")
                            .font(NLFonts.serif(34, weight: .bold))
                            .foregroundColor(NLColor.navy)
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundColor(NLColor.muted)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 30)

                    VStack(alignment: .leading, spacing: NLSpacing.lg) {
                        Text(title)
                            .font(NLFonts.serif(22, weight: .semibold))
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
        AuthShell(title: "Log In", subtitle: "SIGNING AGENT DESK") {
            VStack(spacing: NLSpacing.md) {
                NLTextField(title: "Email", text: $email, keyboardType: .emailAddress)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                NLSecureField(title: "Password", text: $password)
                    .textContentType(.password)

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
        AuthShell(title: "Create Account", subtitle: "SIGNING AGENT DESK") {
            VStack(spacing: NLSpacing.md) {
                HStack(spacing: NLSpacing.md) {
                    NLTextField(title: "First name", text: $firstName)
                    NLTextField(title: "Last name", text: $lastName)
                }
                NLTextField(title: "Email", text: $email, keyboardType: .emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                NLSecureField(title: "Password", text: $password)
                    .textContentType(.newPassword)
                NLSecureField(title: "Confirm password", text: $confirmPassword)
                    .textContentType(.newPassword)

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
            let response = try await APIService.shared.register(
                firstName: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
                lastName: lastName.trimmingCharacters(in: .whitespacesAndNewlines),
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
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
        AuthShell(title: "Forgot Password", subtitle: "SIGNING AGENT DESK") {
            VStack(spacing: NLSpacing.md) {
                NLTextField(title: "Email", text: $email, keyboardType: .emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                BannerView(kind: .success, message: message)
                ErrorBanner(message: errorMessage)

                Button(isSubmitting ? "Sending..." : "Send Reset Link") {
                    Task { await submit() }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isSubmitting)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
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
        AuthShell(title: "Reset Password", subtitle: "SIGNING AGENT DESK") {
            VStack(spacing: NLSpacing.md) {
                NLSecureField(title: "Password", text: $password)
                NLSecureField(title: "Confirm password", text: $confirmPassword)

                BannerView(kind: .success, message: message)
                ErrorBanner(message: errorMessage)

                Button(isSubmitting ? "Resetting..." : "Reset Password") {
                    Task { await submit() }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isSubmitting)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
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
        ZStack {
            ParchmentBackground()
            VStack(spacing: NLSpacing.lg) {
                NLSeal(size: 54)
                Text("Email Verification")
                    .font(NLFonts.serif(24, weight: .bold))
                    .foregroundColor(NLColor.navy)
                Text(state)
                    .font(.subheadline)
                    .foregroundColor(NLColor.muted)
                    .multilineTextAlignment(.center)
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding()
            .nlPanel()
            .padding()
        }
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

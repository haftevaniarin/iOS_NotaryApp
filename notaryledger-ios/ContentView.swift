import SwiftUI

struct ContentView: View {
    @StateObject private var appState: AppState

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--auth-fixtures") {
            SessionStorage.clearSession()
            APIService.shared = AuthUITestFixtures.service()
        }
        #endif
        _appState = StateObject(wrappedValue: AppState())
    }

    var body: some View {
        GeometryReader { geometry in
            Group {
                if appState.isRestoringSession {
                    SessionRestorationView()
                } else {
                    switch appState.route {
                    case .auth:
                        NavigationStack { LoginView() }
                    case .app:
                        LedgerAppShell()
                    case .maintenance(let status):
                        MaintenanceView(status: status)
                    }
                }
            }
            .environment(\.nlViewportWidth, geometry.size.width)
            .font(NLTypography.body)
            .foregroundStyle(NLColor.ink)
        }
        .environmentObject(appState)
        .task {
            await appState.boot()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--auth-fixtures"),
               let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--auth-url=") }),
               let url = URL(string: String(argument.dropFirst("--auth-url=".count))) {
                appState.openURL(url)
            }
            #endif
        }
        .onOpenURL { appState.openURL($0) }
    }
}

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case dashboard
    case journal
    case money
    case more
    case signings
    case rescission
    case invoices
    case expenses
    case customers
    case reports
    case taxSummary
    case billing
    case profile
    case businessCard
    case terms
    case privacy
    case adminAudit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .journal: "Journal"
        case .money: "Accounting"
        case .more: "Menu"
        case .signings: "Signings"
        case .rescission: "Rescission Calculator"
        case .invoices: "Invoices"
        case .expenses: "Expenses"
        case .customers: "Customers"
        case .reports: "Reports"
        case .taxSummary: "Tax Summary"
        case .billing: "Billing"
        case .businessCard: "Digital Business Card"
        case .profile: "Profile"
        case .terms: "Terms & Conditions"
        case .privacy: "Privacy Policy"
        case .adminAudit: "Admin Audit Logs"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: "chart.bar.doc.horizontal"
        case .journal: "book.closed"
        case .money: "dollarsign.circle"
        case .more: "ellipsis"
        case .signings: "doc.text"
        case .rescission: "calendar.badge.clock"
        case .invoices: "doc.richtext"
        case .expenses: "creditcard"
        case .customers: "person.2"
        case .reports: "chart.bar.doc.horizontal"
        case .taxSummary: "sum"
        case .billing: "creditcard.and.123"
        case .businessCard: "person.text.rectangle"
        case .profile: "person.crop.circle"
        case .terms: "doc.plaintext"
        case .privacy: "lock.shield"
        case .adminAudit: "checklist.checked"
        }
    }
}

struct LedgerTopBar: View {
    let title: String
    let onMenu: () -> Void

    var body: some View {
        HStack(spacing: NLSpacing.md) {
                Button(action: onMenu) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 19))
                        .frame(width: 38, height: 38)
                        .foregroundColor(.white)
                        .background(NLColor.navySoft)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .accessibilityLabel("Open navigation menu")

                BrandLockup(compact: true)

                Spacer(minLength: 8)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(minHeight: 58)
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
                        HStack(spacing: NLSpacing.sm) {
                            Text(user.fullName.isEmpty ? "Notary Ledger user" : user.fullName)
                                .font(NLTypography.bodyStrong)
                                .foregroundColor(.white)
                                .lineLimit(1)
                            PlanBadge(billing: appState.billingStatus, unavailable: appState.billingLoadFailed)
                                .accessibilityIdentifier("Sidebar plan")
                        }
                        Text(user.email)
                            .font(NLTypography.caption)
                            .foregroundColor(.white.opacity(0.70))
                            .lineLimit(1)
                    }
                }

                Button {
                    Task { await appState.signOut() }
                } label: {
                    Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                        .font(NLTypography.bodyStrong)
                        .foregroundColor(.white)
                }
            }
            .padding(NLSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NLColor.navySoft.opacity(0.55))
        }
        .frame(width: 264)
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
            .font(NLFonts.sans(14, weight: .medium))
            .foregroundColor(selectedSection == section ? .white : Color(red: 0.718, green: 0.753, blue: 0.855))
            .padding(.horizontal, NLSpacing.md)
            .padding(.vertical, 10)
            .background(selectedSection == section ? NLColor.navySoft : Color.white.opacity(0.0001))
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
            GeometryReader { geometry in
            ScrollView {
                VStack(spacing: NLSpacing.xl) {
                    VStack(spacing: NLSpacing.sm) {
                        NLSeal(size: 52)
                        Text("Notary Ledger")
                            .font(NLFonts.serif(22))
                            .foregroundColor(NLColor.navy)
                        Text(subtitle)
                            .font(NLFonts.sans(11.5))
                            .tracking(0.69)
                            .foregroundColor(NLColor.muted)
                            .multilineTextAlignment(.center)
                    }

                    NLCard(inset: 28) {
                        VStack(alignment: .leading, spacing: NLSpacing.lg) {
                            Text(title)
                                .id("authHeading")
                                .font(NLFonts.serif(20))
                                .foregroundColor(NLColor.ink)
                            content
                        }
                    }
                }
                .frame(maxWidth: 410)
                .padding(24)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
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
                    .font(NLFonts.serif(20))
                    .foregroundColor(NLColor.navy)
                Text(status.message ?? "Notary Ledger is temporarily unavailable. Please try again soon.")
                    .font(NLTypography.body)
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
        .navigationTitle("Menu")
        .scrollContentBackground(.hidden)
        .background(ParchmentBackground())
    }
}

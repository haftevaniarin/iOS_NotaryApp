import SwiftUI

enum LedgerTab: String, CaseIterable, Identifiable {
    case home, signings, money, more
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var systemImage: String {
        switch self {
        case .home: "house"
        case .signings: "doc.text"
        case .money: "dollarsign.circle"
        case .more: "person.crop.circle"
        }
    }
    var root: AppSection {
        switch self {
        case .home: .dashboard
        case .signings: .signings
        case .money: .money
        case .more: .more
        }
    }
    init(section: AppSection) {
        switch section {
        case .dashboard: self = .home
        case .signings: self = .signings
        case .money, .invoices, .expenses, .taxSummary: self = .money
        default: self = .more
        }
    }
}

struct LedgerAppShell: View {
    var dashboardModel: DashboardViewModel? = nil
    @EnvironmentObject private var appState: AppState
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: LedgerTab = .home
    @State private var moneyPath: [AppSection] = []
    @State private var morePath: [AppSection] = []
    @State private var profileIcon = ProfileTabIconStore()
    private var profileIdentity: ProfileTabIdentity { ProfileTabIdentity(user: appState.currentUser) }
    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { home.toolbar(.hidden, for: .navigationBar) }
                .tabItem { Label("Home", systemImage: LedgerTab.home.systemImage) }.tag(LedgerTab.home)
            NavigationStack { SigningsView().toolbar(.hidden, for: .navigationBar) }
                .tabItem { Label("Signings", systemImage: LedgerTab.signings.systemImage) }.tag(LedgerTab.signings)
            NavigationStack(path: $moneyPath) {
                LedgerDestinationsView(money: true)
                    .navigationDestination(for: AppSection.self) { LedgerFeatureView(section: $0) }
            }.tabItem { Label("Money", systemImage: LedgerTab.money.systemImage) }.tag(LedgerTab.money)
            NavigationStack(path: $morePath) {
                LedgerDestinationsView(money: false)
                    .navigationDestination(for: AppSection.self) { LedgerFeatureView(section: $0) }
            }.tabItem {
                Label { Text("More") } icon: { Image(uiImage: profileIcon.image(for: profileIdentity)).renderingMode(.original) }
            }.tag(LedgerTab.more)
        }.tint(Color.brassText)
            .task(id: profileIdentity) { await profileIcon.load(profileIdentity) }
            .toolbarBackground(Color.parchment, for: .tabBar).toolbarBackground(.visible, for: .tabBar)
            .onAppear { route(to: appState.selectedSection) }
            .onChange(of: appState.selectedSection) { _, section in route(to: section) }
            .onChange(of: selectedTab) { _, tab in
                switch tab {
                case .money: appState.selectedSection = moneyPath.last ?? .money
                case .more: appState.selectedSection = morePath.last ?? .more
                default: appState.selectedSection = tab.root
                }
            }
            .onChange(of: moneyPath) { _, path in if selectedTab == .money, LedgerTab(section: appState.selectedSection) == .money { appState.selectedSection = path.last ?? .money } }
            .onChange(of: morePath) { _, path in if selectedTab == .more, LedgerTab(section: appState.selectedSection) == .more { appState.selectedSection = path.last ?? .more } }
            .onChange(of: scenePhase) { _, phase in if phase == .active, dashboardModel == nil { Task { await appState.refreshBillingStatus() } } }
    }
    @ViewBuilder private var home: some View {
        if let dashboardModel { DashboardView(model: dashboardModel) }
        else { LedgerDashboardHost(appState: appState).id(appState.currentUser?.id) }
    }
    private func route(to section: AppSection) {
        let tab = LedgerTab(section: section)
        if tab == .money {
            if section == .money { moneyPath = [] }
            else if moneyPath.last != section { moneyPath = [section] }
        } else if tab == .more {
            if section == .more { morePath = [] }
            else if morePath.last != section { morePath = [section] }
        }
        selectedTab = tab
    }
}

private struct LedgerDestinationsView: View {
    let money: Bool
    @EnvironmentObject private var appState: AppState
    private var sections: [AppSection] {
        if money { return [.invoices, .expenses, .taxSummary] }
        let base: [AppSection] = [.journal, .rescission, .customers, .billing, .businessCard, .profile, .terms, .privacy]
        return appState.currentUser?.canAccessAdminAudit == true ? base + [.adminAudit] : base
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NLSpacing.lg) {
                ScreenTitleBlock(title: money ? "Money" : "More", subtitle: money ? "Invoices, expenses, and reports." : "Manage your Notary Ledger account.")
                if !money {
                    HStack {
                        Text(appState.currentUser?.fullName ?? "Notary Ledger").font(NLTypography.bodyStrong)
                        Spacer()
                        PlanBadge(billing: appState.billingStatus, unavailable: appState.billingLoadFailed).accessibilityIdentifier("More plan")
                    }
                }
                NLCard {
                    VStack(spacing: 0) {
                        ForEach(sections) { section in
                            NavigationLink(value: section) {
                                HStack(spacing: 12) {
                                    Image(systemName: section.systemImage).frame(width: 22).accessibilityHidden(true)
                                    Text(section.title).frame(maxWidth: .infinity, alignment: .leading)
                                    Image(systemName: "chevron.right").font(.caption).accessibilityHidden(true)
                                }.font(NLTypography.bodyStrong).foregroundStyle(NLColor.navy).frame(minHeight: 48)
                            }
                            if section != sections.last { Divider() }
                        }
                    }
                }
                if !money {
                    Button("Log Out") { Task { await appState.signOut() } }.buttonStyle(SecondaryButtonStyle())
                }
            }.nlScreenPadding()
        }.background(ParchmentBackground()).navigationBarTitleDisplayMode(.inline)
    }
}

private struct LedgerFeatureView: View {
    let section: AppSection
    var body: some View {
        content.navigationTitle(section.title).navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(NLColor.parchment, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
    }
    @ViewBuilder private var content: some View {
        switch section {
        case .dashboard: DashboardView()
        case .signings: SigningsView()
        case .journal: DashboardTabPlaceholder(route: .journal)
        case .money, .more: LedgerDestinationsView(money: section == .money)
        case .rescission: RescissionCalculatorView()
        case .invoices: InvoicesView()
        case .expenses: ExpensesView()
        case .customers: CustomersView()
        case .taxSummary: TaxSummaryView()
        case .billing: BillingView()
        case .profile: ProfileView()
        case .businessCard: BusinessCardView()
        case .terms: LegalDocumentView(kind: .terms)
        case .privacy: LegalDocumentView(kind: .privacy)
        case .adminAudit: AdminAuditLogsView()
        }
    }
}

private struct DashboardTabPlaceholder: View {
    let route: DashboardRoute
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: route.systemImage).font(.system(size: 32)).foregroundStyle(Color.brassText).accessibilityHidden(true)
            Text(route.title).font(DashboardTheme.heading(26))
            Text("Journal entries will be available here.").font(DashboardTheme.body(14)).foregroundStyle(Color.muted)
                .multilineTextAlignment(.center)
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.parchment.ignoresSafeArea())
    }
}

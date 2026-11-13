import SwiftUI

struct DashboardView: View {
    @State private var model: DashboardViewModel
    let onRoute: (DashboardRoute) -> Void
    let onNavigate: (Signing) -> Void
    let onSeeAll: () -> Void

    init(model: DashboardViewModel, onRoute: @escaping (DashboardRoute) -> Void = { _ in }, onNavigate: @escaping (Signing) -> Void = { _ in }, onSeeAll: @escaping () -> Void = {}) {
        _model = State(initialValue: model); self.onRoute = onRoute; self.onNavigate = onNavigate; self.onSeeAll = onSeeAll
    }
    init(repository: (any DashboardRepository)? = nil, onRoute: @escaping (DashboardRoute) -> Void = { _ in }, onNavigate: @escaping (Signing) -> Void = { _ in }, onSeeAll: @escaping () -> Void = {}) {
        self.init(model: DashboardViewModel(repository: repository ?? InMemoryDashboardRepository(snapshot: .empty)), onRoute: onRoute, onNavigate: onNavigate, onSeeAll: onSeeAll)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DashboardTheme.sectionGap) {
                header
                if let error = model.errorMessage {
                    errorState(error)
                } else if model.isLoading {
                    dashboardContents(signing: PreviewData.loadingNext, stats: PreviewData.loading.monthStats,
                                      attention: PreviewData.loading.attentionItems, upcoming: PreviewData.loadingUpcoming)
                        .redacted(reason: .placeholder).disabled(true).accessibilityHidden(true)
                } else {
                    dashboardContents(signing: model.nextSigning, stats: model.monthStats, attention: model.attentionItems, upcoming: model.upcoming)
                }
            }.padding(.horizontal, DashboardTheme.horizontalPadding).padding(.top, 16).padding(.bottom, 24)
                .frame(maxWidth: 600).frame(maxWidth: .infinity, alignment: .top)
        }.background(Color.parchment.ignoresSafeArea()).foregroundStyle(Color.ink)
            .accessibilityIdentifier("dashboard-content")
            .refreshable { await model.load() }
            .task { if model.loadsOnAppear { await model.load() } }
    }
    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.dateLabel).font(DashboardTheme.body(12, weight: .semibold)).tracking(0.96).foregroundStyle(Color.brassText)
                Text(model.greeting).font(DashboardTheme.heading(32)).accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("dashboard-greeting")
                if model.isLoading {
                    Text("Loading dashboard…").font(DashboardTheme.body(14)).foregroundStyle(Color.muted)
                        .accessibilityIdentifier("dashboard-loading")
                }
            }.frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            Button { onRoute(.notifications) } label: {
                Image(systemName: "bell").font(.system(size: 18)).foregroundStyle(Color.ink)
                    .frame(width: 44, height: 44).background(Color.card, in: Circle())
                    .overlay(Circle().stroke(Color.cardBorder, lineWidth: 1))
            }.buttonStyle(.plain).accessibilityLabel("Notifications")
        }
    }
    private func dashboardContents(signing: Signing?, stats: MonthStats, attention: [AttentionItem], upcoming: [Signing]) -> some View {
        Group {
            NextSigningCard(signing: signing, onNavigate: onNavigate, onOpen: { onRoute(.signingFile($0.id)) })
            QuickActionsRow(onSelect: onRoute)
            MonthStatsGrid(stats: stats, month: model.monthLabel, previousMonth: model.previousMonthLabel)
            AttentionList(items: attention, onSelect: onRoute)
            UpcomingList(signings: upcoming, onSelect: { onRoute(.signingFile($0.id)) }, onSeeAll: onSeeAll)
        }
    }
    private func errorState(_ error: String) -> some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Dashboard unavailable", systemImage: "exclamationmark.triangle").font(DashboardTheme.body(15, weight: .semibold))
                Text(error).font(DashboardTheme.body(14)).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
                Button("Try again") { Task { await model.load() } }
                    .font(DashboardTheme.body(14, weight: .semibold)).foregroundStyle(Color.brassText).frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("dashboard-retry")
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
        }.accessibilityIdentifier("dashboard-error")
    }
}

#if DEBUG
private struct DashboardPreview: View {
    let model: DashboardViewModel
    @StateObject private var appState = AppState()
    var body: some View { LedgerAppShell(dashboardModel: model).environmentObject(appState).preferredColorScheme(.light) }
}

#Preview("Dashboard · Loaded", traits: .fixedLayout(width: 390, height: 844)) {
    DashboardPreview(model: PreviewData.loadedModel)
}
#Preview("Dashboard · Empty", traits: .fixedLayout(width: 390, height: 844)) {
    DashboardPreview(model: PreviewData.emptyModel)
}
#Preview("Dashboard · Loading", traits: .fixedLayout(width: 390, height: 844)) {
    DashboardPreview(model: PreviewData.loadingModel)
}
#Preview("Dashboard · Error", traits: .fixedLayout(width: 390, height: 844)) {
    DashboardPreview(model: PreviewData.errorModel)
}
#Preview("Dashboard · AX3", traits: .fixedLayout(width: 390, height: 844)) {
    DashboardPreview(model: PreviewData.loadedModel).dynamicTypeSize(.accessibility3)
}
#endif

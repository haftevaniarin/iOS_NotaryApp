import SwiftUI

struct BillingOverviewView: View {
    @State private var model: BillingViewModel
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var appState: AppState

    init(store: SubscriptionStore) { _model = State(initialValue: BillingViewModel(store: store)) }
    init(model: BillingViewModel) { _model = State(initialValue: model) }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if model.isInitialLoading {
                        loadingCard
                    } else if model.subscription != nil {
                        subscriptionCard
                    }
                    if let error = model.error { retryNotice(error) }
                    if model.cancellationScheduled { BillingMessage(text: model.cancellationNotice) }
                    if model.store.pendingUpdate { BillingMessage(text: "Your subscription update is waiting for Stripe confirmation. Refresh to check again.") }
                    if let issue = model.subscription?.paymentIssue { BillingMessage(text: issue.message) }
                    if let text = model.store.availabilityMessage { BillingMessage(text: text) }
                    Spacer(minLength: 20)
                    VStack(spacing: 12) {
                        Text("Changes appear after Stripe confirms them with the backend.")
                            .font(NLTypography.caption).foregroundStyle(Theme.mutedText).multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                        Button { Task { await model.manage() } } label: {
                            HStack(spacing: 8) {
                                Text(model.store.busy ? "Opening Stripe…" : "Manage subscription")
                                Image(systemName: "arrow.up.right").accessibilityHidden(true)
                            }
                        }.buttonStyle(BillingActionStyle()).disabled(!model.canManage)
                            .accessibilityIdentifier("billing-manage-subscription")
                        NavigationLink { PlansView(model: model) } label: { Text("View plans") }
                            .buttonStyle(BillingOutlineStyle()).disabled(model.subscription == nil)
                            .accessibilityIdentifier("billing-view-plans")
                    }
                }.padding(.horizontal, 22).padding(.vertical, 20)
                    .frame(maxWidth: 600, minHeight: max(0, geometry.size.height), alignment: .topLeading)
                    .frame(maxWidth: .infinity)
            }.refreshable { await model.refresh() }
        }.foregroundStyle(Theme.inkNavy).background(Theme.parchment.ignoresSafeArea())
            .task(id: model.store.accountID) { await model.refresh() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await model.refresh() } } }
            .onChange(of: model.store.accountID) { _, _ in model.browser = nil }
            .onChange(of: appState.billingReturnRevision) { _, _ in Task { await model.returnedFromStripe() } }
            .sheet(item: $model.browser, onDismiss: { Task { await model.refresh() } }) { session in
                StripeSafariView(url: session.url) { model.browser = nil }.ignoresSafeArea()
            }
    }
    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            ScreenTitleBlock(title: "Billing", subtitle: "Manage your NotaryLedger subscription.")
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Button { Task { await model.refresh() } } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 18, weight: .medium))
                    .frame(width: 44, height: 44).background(Theme.parchmentCard, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.parchmentLine, lineWidth: 1))
            }.buttonStyle(.plain).accessibilityLabel("Refresh").accessibilityIdentifier("billing-refresh")
                .disabled(model.isLoading || model.store.busy)
        }
    }
    private var subscriptionCard: some View {
        BillingPanel {
            VStack(alignment: .leading, spacing: 16) {
                ViewThatFits(in: .horizontal) {
                    HStack { subscriptionTitle; Spacer(minLength: 8); statusPill }
                    VStack(alignment: .leading, spacing: 10) { subscriptionTitle; statusPill }
                }
                subscriptionRow("PLAN", value: model.planName)
                line
                subscriptionRow("STATE", value: model.stateLabel)
                line
                subscriptionRow("BILLING", value: model.billingPrice, detail: model.billingInterval)
                line
                subscriptionRow("CURRENT PERIOD", value: model.currentPeriodLabel)
            }
        }.accessibilityIdentifier("billing-subscription-card")
    }
    private var subscriptionTitle: some View { Text("Subscription").font(NLTypography.cardTitle).accessibilityAddTraits(.isHeader) }
    private var statusPill: some View {
        BillingPill(text: (model.activeStatus ? "● " : "") + model.statusLabel,
                    fill: model.activeStatus ? Theme.activeGreenFill : model.warningStatus ? Theme.noticeFill : Theme.parchmentTrack,
                    textColor: model.activeStatus ? Theme.activeGreenText : model.warningStatus ? Theme.brassText : Theme.mutedText)
    }
    private var line: some View { Rectangle().fill(Theme.parchmentLine).frame(height: 1).accessibilityHidden(true) }
    private func subscriptionRow(_ label: String, value: String, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(NLTypography.label).tracking(1.1).foregroundStyle(Theme.mutedText)
            Text(value).font(NLTypography.bodyStrong).fixedSize(horizontal: false, vertical: true)
            if let detail { Text(detail).font(NLTypography.caption).foregroundStyle(Theme.mutedText) }
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
    }
    private var loadingCard: some View {
        BillingPanel {
            VStack(alignment: .leading, spacing: 24) {
                Text("Loading subscription…").font(NLTypography.cardTitle)
                ForEach(0..<4) { _ in
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 4).fill(Theme.parchmentTrack).frame(width: 80, height: 12)
                        RoundedRectangle(cornerRadius: 4).fill(Theme.parchmentTrack).frame(maxWidth: 220).frame(height: 22)
                    }.accessibilityHidden(true)
                }
            }
        }.accessibilityIdentifier("billing-loading")
    }
    private func retryNotice(_ text: String) -> some View {
        BillingMessage {
            VStack(alignment: .leading, spacing: 8) {
                Text(text).font(NLTypography.body)
                Button("Retry") { Task { await model.refresh() } }
                    .font(NLTypography.bodyStrong).frame(minHeight: 44).disabled(model.isLoading)
                    .accessibilityIdentifier("billing-retry")
            }
        }
    }
}

#if DEBUG
#Preview("Billing · Pro active", traits: .fixedLayout(width: 390, height: 844)) {
    NavigationStack { BillingOverviewView(store: .preview(interval: .annual)) }.environmentObject(AppState())
}
#Preview("Billing · Cancellation scheduled", traits: .fixedLayout(width: 390, height: 844)) {
    NavigationStack { BillingOverviewView(store: .preview(interval: .annual, cancellationScheduled: true)) }.environmentObject(AppState())
}
#Preview("Billing · Free", traits: .fixedLayout(width: 390, height: 844)) {
    NavigationStack { BillingOverviewView(store: .preview(tier: .free)) }.environmentObject(AppState())
}
#Preview("Billing · Loading", traits: .fixedLayout(width: 390, height: 844)) {
    NavigationStack { BillingOverviewView(store: .preview(loading: true)) }.environmentObject(AppState())
}
#Preview("Billing · Error", traits: .fixedLayout(width: 390, height: 844)) {
    NavigationStack { BillingOverviewView(store: .preview(error: "Subscription information could not be loaded. Please try again.")) }.environmentObject(AppState())
}
#endif

import SwiftUI

struct PlansView: View {
    @Bindable var model: BillingViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Button { dismiss() } label: {
                    Label("Billing", systemImage: "chevron.left").font(NLTypography.bodyStrong)
                        .foregroundStyle(Theme.brassText).frame(minHeight: 44)
                }.buttonStyle(.plain).accessibilityLabel("Back to Billing").accessibilityIdentifier("plans-back")
                ScreenTitleBlock(title: "Plans", subtitle: nil).accessibilityAddTraits(.isHeader)
                BillingIntervalControl(selection: $model.selectedInterval, savings: model.store.savings())
                    .disabled(!model.canSelectInterval)
                if model.cancellationScheduled {
                    Text("Switching interval is unavailable while cancellation is scheduled.")
                        .font(NLTypography.caption).foregroundStyle(Theme.mutedText)
                }
                if !model.hasSubscription { freeCard }
                proCard
                if let error = model.error { BillingMessage(text: error) }
                if let text = model.store.availabilityMessage { BillingMessage(text: text) }
            }.padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 22).frame(maxWidth: 600).frame(maxWidth: .infinity)
        }.foregroundStyle(Theme.inkNavy).background(Theme.parchment.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
    }
    private var freeCard: some View {
        BillingPanel {
            VStack(alignment: .leading, spacing: 12) {
                planTitle(.free)
                Text(model.freePrice).font(NLTypography.metric)
                Text(PlanTier.free.definition.featureLine).font(NLTypography.body).foregroundStyle(Theme.mutedText)
            }
        }.accessibilityElement(children: .combine).accessibilityIdentifier("plans-free")
    }
    private var proCard: some View {
        BillingPanel(border: Theme.brassDeep, borderWidth: 2) {
            VStack(alignment: .leading, spacing: 12) {
                planTitle(.pro)
                Text(model.proPrice).font(NLTypography.metric).fixedSize(horizontal: false, vertical: true)
                if let detail = model.annualDetail { Text(detail).font(NLTypography.caption).foregroundStyle(Theme.mutedText) }
                Text(PlanTier.pro.definition.featureLine).font(NLTypography.body).foregroundStyle(Theme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
                Button(model.hasSubscription ? "Subscribed" : model.store.busy ? "Opening Stripe…" : "Subscribe") {
                    Task { await model.subscribe() }
                }.buttonStyle(BillingActionStyle(disabledFill: model.hasSubscription ? Theme.disabledButton : nil))
                    .disabled(!model.canSubscribe).accessibilityIdentifier("plans-subscribe")
            }
        }
    }
    private func planTitle(_ tier: PlanTier) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) { title(tier); Spacer(minLength: 8); pill(tier) }
            VStack(alignment: .leading, spacing: 10) { title(tier); pill(tier) }
        }
    }
    private func title(_ tier: PlanTier) -> some View { Text(tier.definition.name).font(NLTypography.cardTitle).accessibilityAddTraits(.isHeader) }
    private func pill(_ tier: PlanTier) -> some View {
        BillingPill(text: tier == .free ? "FREE" : "PRO", fill: tier == .free ? Theme.noticeFill : Theme.activeGreenFill,
                    textColor: tier == .free ? Theme.brassText : Theme.activeGreenText)
    }
}

#if DEBUG
#Preview("Plans · Annual", traits: .fixedLayout(width: 390, height: 844)) {
    NavigationStack { PlansView(model: BillingViewModel(store: .preview(tier: .free))) }
}
#Preview("Plans · Monthly", traits: .fixedLayout(width: 390, height: 844)) {
    let model = BillingViewModel(store: .preview(tier: .free)); model.selectedInterval = .monthly
    return NavigationStack { PlansView(model: model) }
}
#Preview("Plans · Subscribed", traits: .fixedLayout(width: 390, height: 844)) {
    NavigationStack { PlansView(model: BillingViewModel(store: .preview(interval: .annual))) }
}
#Preview("Plans · Cancellation scheduled", traits: .fixedLayout(width: 390, height: 844)) {
    NavigationStack { PlansView(model: BillingViewModel(store: .preview(cancellationScheduled: true))) }
}
#endif

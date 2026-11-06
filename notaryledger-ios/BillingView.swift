import SwiftUI

struct BillingView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    private var billing: BillingStatusPayload? { appState.billingStatus }
    @State private var interval = "monthly"
    @State private var busy = false
    @State private var error = ""
    @AppStorage("notary_pending_checkout_owner") private var pendingOwner = ""
    @AppStorage("notary_pending_checkout") private var pendingCheckout = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NLSpacing.lg) {
                ScreenTitleBlock(title: "Billing", subtitle: "Manage the plan and billing access attached to this Notary Ledger account.")
                ErrorBanner(message: error)
                if busy { ProgressView() }
                if let billing {
                    NLCard {
                        VStack(alignment: .leading, spacing: NLSpacing.md) {
                            Text(billing.hasProAccess ? "Notary Ledger Pro" : "Notary Ledger Free").font(NLFonts.serif(17)).foregroundColor(NLColor.navy)
                            DetailRow(label: "Status", value: billing.subscriptionStatus ?? "Unknown")
                            if let current = billing.billingInterval { DetailRow(label: "Billing interval", value: current.capitalized) }
                            if let end = billing.currentPeriodEnd { DetailRow(label: billing.cancelAtPeriodEnd == true ? "Access until" : "Current period ends", value: end) }
                            if let remaining = billing.remainingFreeOrders, !billing.hasProAccess { DetailRow(label: "Free orders remaining", value: String(remaining)) }
                            if billing.cancelAtPeriodEnd == true { BannerView(kind: .warning, message: "Your subscription will not renew. Access follows the current billing period.") }
                            if let change = billing.scheduledChange {
                                DetailRow(label: "Scheduled interval", value: change.billingInterval ?? "Pending")
                                if let date = change.effectiveAt { DetailRow(label: "Effective", value: date) }
                                Button("Cancel Scheduled Change") { Task { await changeInterval(nil) } }.disabled(busy)
                            }
                        }
                    }
                    NLCard {
                        VStack(spacing: NLSpacing.md) {
                            Picker("Billing interval", selection: $interval) {
                                Text("Monthly").tag("monthly")
                                Text("Annual").tag("annual")
                            }.pickerStyle(.segmented)
                            if billing.hasProAccess {
                                Button("Schedule Billing Interval Change") { Task { await changeInterval(interval) } }.buttonStyle(SecondaryButtonStyle()).disabled(busy || interval == billing.billingInterval)
                            } else {
                                Button("Upgrade to Pro") { Task { await checkout() } }.buttonStyle(PrimaryButtonStyle()).disabled(busy)
                            }
                            Button("Manage Billing") { Task { await portal() } }.buttonStyle(SecondaryButtonStyle()).disabled(busy)
                            Text("Stripe opens in your browser. Return here to refresh the confirmed billing status.").font(NLTypography.caption).foregroundColor(NLColor.muted)
                        }
                    }
                }
                Button("Refresh Billing Status") { Task { await load() } }.buttonStyle(SecondaryButtonStyle()).disabled(busy)
            }.nlScreenPadding()
        }.background(ParchmentBackground()).task { await load() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await load() } } }
    }
    private func load() async {
        guard !busy, let owner = appState.currentUser?.id else { return }
        busy = true; error = ""
        defer { busy = false }
        do {
            if pendingOwner != appState.currentUser?.id { pendingCheckout = ""; pendingOwner = "" }
            if !pendingCheckout.isEmpty {
                do {
                    let result = try await APIService.shared.syncCheckoutSession(sessionId: pendingCheckout)
                    appState.updateBillingStatus(result, for: owner)
                    pendingCheckout = ""
                }
                catch { self.error = error.localizedDescription }
            }
            let result = try await APIService.shared.fetchBillingStatus()
            appState.updateBillingStatus(result, for: owner)
        } catch { self.error = error.localizedDescription }
    }
    private func checkout() async {
        busy = true; error = ""
        defer { busy = false }
        do {
            let session = try await APIService.shared.createCheckoutSession(billingInterval: interval)
            guard let value = session.url, let url = URL(string: value), url.scheme == "https" else { throw APIError.invalidResponse }
            pendingCheckout = session.sessionId ?? ""
            pendingOwner = appState.currentUser?.id ?? ""
            openURL(url) { accepted in if !accepted { error = "Could not open Stripe checkout." } }
        } catch { self.error = error.localizedDescription }
    }
    private func portal() async {
        busy = true; error = ""
        defer { busy = false }
        do {
            let session = try await APIService.shared.createCustomerPortalSession()
            guard let value = session.url, let url = URL(string: value), url.scheme == "https" else { throw APIError.invalidResponse }
            openURL(url) { accepted in if !accepted { error = "Could not open the billing portal." } }
        } catch { self.error = error.localizedDescription }
    }
    private func changeInterval(_ value: String?) async {
        guard let owner = appState.currentUser?.id else { return }
        busy = true; error = ""
        defer { busy = false }
        do {
            let result = try await APIService.shared.changeBillingInterval(value)
            appState.updateBillingStatus(result, for: owner)
        }
        catch { self.error = error.localizedDescription }
    }
}

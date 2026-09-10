import SwiftUI

enum BillingStatus: String, CaseIterable, Identifiable {
    case free = "Free"
    case pro = "Pro"
    case pastDue = "Past Due"
    case canceled = "Canceled"
    case inactive = "Inactive"

    var id: String { rawValue }
}

struct BillingView: View {
    @State private var status: BillingStatus = .free
    @State private var showUpgrade = false
    @State private var showPortal = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NLSpacing.lg) {
                ScreenTitleBlock(
                    title: "Billing",
                    subtitle: "Manage the plan and billing access attached to this Notary Ledger account."
                )

                planCard
                stateBanner
                actionsCard

                NLCard {
                    VStack(alignment: .leading, spacing: NLSpacing.md) {
                        Text("Preview Billing States")
                            .font(.headline)
                            .foregroundColor(NLColor.navy)
                        Picker("Status", selection: $status) {
                            ForEach(BillingStatus.allCases) { state in
                                Text(state.rawValue).tag(state)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
            }
            .padding(NLSpacing.lg)
        }
        .background(ParchmentBackground())
        .sheet(isPresented: $showUpgrade) {
            UpgradeToProSheet(status: $status)
        }
        .sheet(isPresented: $showPortal) {
            BillingPortalSheet(status: status)
        }
    }

    private var planCard: some View {
        NLCard {
            VStack(alignment: .leading, spacing: NLSpacing.md) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Current Plan")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(NLColor.muted)
                        Text(status == .pro ? "Notary Ledger Pro" : "Notary Ledger Free")
                            .font(NLFonts.serif(24, weight: .bold))
                            .foregroundColor(NLColor.navy)
                    }
                    Spacer()
                    Text(status.rawValue)
                        .font(.caption.weight(.bold))
                        .foregroundColor(status == .pastDue ? NLColor.warning : NLColor.navy)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(NLColor.brass.opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }

                DetailRow(label: "Invoice tools", value: status == .free ? "Limited" : "Included")
                DetailRow(label: "Tax exports", value: status == .free ? "Preview" : "PDF export")
                DetailRow(label: "Customer history", value: "Included")
            }
        }
    }

    @ViewBuilder
    private var stateBanner: some View {
        switch status {
        case .free:
            BannerView(kind: .info, message: "Upgrade to Pro to unlock full invoice and tax export workflows.")
        case .pro:
            BannerView(kind: .success, message: "Your Pro subscription is active.")
        case .pastDue:
            BannerView(kind: .warning, message: "Payment is past due. Update billing to keep Pro features available.")
        case .canceled:
            BannerView(kind: .warning, message: "Your subscription is canceled and will not renew.")
        case .inactive:
            BannerView(kind: .error, message: "Billing is inactive. Choose a plan to restore paid features.")
        }
    }

    private var actionsCard: some View {
        NLCard {
            VStack(spacing: NLSpacing.md) {
                Button {
                    showUpgrade = true
                } label: {
                    Label(status == .free || status == .inactive ? "Upgrade to Pro" : "Review Plan", systemImage: "arrow.up.circle")
                }
                .buttonStyle(PrimaryButtonStyle())

                Button {
                    showPortal = true
                } label: {
                    Label("Manage Billing", systemImage: "creditcard")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }
}

struct UpgradeToProSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var status: BillingStatus
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: NLSpacing.lg) {
            Text("Upgrade to Pro")
                .font(NLFonts.serif(24, weight: .bold))
                .foregroundColor(NLColor.navy)
            Text("Continue to Stripe checkout to activate Pro billing for invoice PDFs, tax exports, and expanded ledger workflows.")
                .font(.subheadline)
                .foregroundColor(NLColor.muted)
            BannerView(kind: .info, message: "Checkout opens in the connected web billing flow when the production endpoint is configured.")
            Button(isLoading ? "Opening..." : "Continue to Checkout") {
                isLoading = true
                status = .pro
                dismiss()
            }
            .buttonStyle(PrimaryButtonStyle())
            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .padding()
        .presentationDetents([.medium])
    }
}

struct BillingPortalSheet: View {
    @Environment(\.dismiss) private var dismiss
    let status: BillingStatus

    var body: some View {
        VStack(alignment: .leading, spacing: NLSpacing.lg) {
            Text("Manage Billing")
                .font(NLFonts.serif(24, weight: .bold))
                .foregroundColor(NLColor.navy)
            Text("Stripe account portal")
                .font(.headline)
                .foregroundColor(NLColor.navy)
            Text(status == .free ? "No paid subscription is attached to this account yet." : "Open the billing portal to update payment method, invoices, and subscription status.")
                .font(.subheadline)
                .foregroundColor(NLColor.muted)
            Button("Done") {
                dismiss()
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding()
        .presentationDetents([.height(280)])
    }
}

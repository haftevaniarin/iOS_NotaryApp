import SwiftUI

struct CustomersView: View {
    @EnvironmentObject private var appState: AppState
    @State private var searchText = ""
    @State private var exportItem: ShareURL?
    @State private var generatingCustomerID: String?
    @State private var errorCustomerID: String?
    @State private var errorMessage = ""

    private var summaries: [CustomerSummary] {
        CustomerSummaries.build(from: appState.orders).filter { summary in
            searchText.isEmpty || summary.displayName.lowercased().contains(searchText.lowercased())
        }
    }

    var body: some View {
        ZStack {
            ParchmentBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: NLSpacing.lg) {
                    ScreenTitleBlock(title: "Customers", subtitle: "Customer cards are derived from signing history.")
                    NLTextField(title: "Search customers", text: $searchText)
                        .nlPanel()

                    if summaries.isEmpty {
                        EmptyStateView(title: "No customers found", systemImage: "person.2", message: "Customers are derived from signing history.")
                    } else {
                        SectionHeader(title: "Customers")
                        ForEach(summaries) { summary in
                            CustomerSummaryCard(
                                summary: summary,
                                isGenerating: generatingCustomerID == summary.id,
                                invoiceActionsDisabled: generatingCustomerID != nil,
                                errorMessage: errorCustomerID == summary.id ? errorMessage : ""
                            ) {
                                Task { await generateInvoice(for: summary) }
                            }
                        }
                    }
                }
                .nlScreenPadding()
            }
        }
        .onDisappear { searchText = "" }
        .sheet(item: $exportItem) { ShareSheet(activityItems: [$0.url]) }
    }

    private func generateInvoice(for customer: CustomerSummary) async {
        guard generatingCustomerID == nil, !customer.invoiceCandidates.isEmpty else { return }
        generatingCustomerID = customer.id
        errorCustomerID = nil
        errorMessage = ""
        defer { generatingCustomerID = nil }

        do {
            let billing = try await APIService.shared.fetchBillingStatus()
            guard billing.features?["invoiceGeneration"] == true else {
                throw APIError.serverError("Upgrade to Pro to generate invoices.")
            }
            exportItem = ShareURL(url: try LedgerPDF.invoice(
                user: appState.currentUser,
                customer: customer.displayName,
                orders: customer.invoiceCandidates
            ))
        } catch {
            errorCustomerID = customer.id
            errorMessage = error.localizedDescription
        }
    }
}

struct CustomerSummaryCard: View {
    let summary: CustomerSummary
    var isGenerating = false
    var invoiceActionsDisabled = false
    var errorMessage = ""
    let onCreateInvoice: () -> Void

    var body: some View {
        NLCard {
            VStack(alignment: .leading, spacing: NLSpacing.md) {
                HStack(alignment: .top) {
                    Text(summary.displayName)
                        .font(NLTypography.cardTitle)
                        .foregroundColor(NLColor.ink)
                    Spacer()
                    Text(summary.revenue.currencyString)
                        .font(NLFonts.mono(15, weight: .semibold))
                        .foregroundColor(NLColor.navy)
                }
                DetailRow(label: "Latest signing", value: summary.orders.first?.displayDate ?? "-")
                DetailRow(label: "Signing count", value: "\(summary.signingCount)")
                DetailRow(label: "Unpaid work", value: "\(summary.unpaidCount)")
                DetailRow(label: "Revenue", value: summary.revenue.currencyString)
                ErrorBanner(message: errorMessage)
                if summary.invoiceCandidates.isEmpty {
                    Button {
                    } label: {
                        Label("No Invoice Due", systemImage: "doc.richtext")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(true)
                    .accessibilityIdentifier("customer-invoice-\(summary.id)")
                } else {
                    Button(action: onCreateInvoice) {
                        Label(isGenerating ? "Generating..." : "Create Invoice", systemImage: "doc.richtext")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(invoiceActionsDisabled)
                    .accessibilityIdentifier("customer-invoice-\(summary.id)")
                }
            }
        }
    }
}

struct CustomerDetailView: View {
    let summary: CustomerSummary

    var body: some View {
        ZStack {
            ParchmentBackground()
            List {
                Section("Summary") {
                    DetailRow(label: "Signing Count", value: "\(summary.signingCount)")
                    DetailRow(label: "Unpaid Count", value: "\(summary.unpaidCount)")
                    DetailRow(label: "Revenue", value: summary.revenue.currencyString)
                    DetailRow(label: "Invoice Candidates", value: "\(summary.invoiceCandidates.count)")
                }

                Section("Signing History") {
                    ForEach(summary.orders) { order in
                        SigningOrderCompactRow(order: order)
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(summary.displayName)
    }
}

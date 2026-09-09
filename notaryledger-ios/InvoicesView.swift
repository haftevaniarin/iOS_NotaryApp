import SwiftUI

struct InvoicesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedCustomerID: String?
    @State private var generatedInvoice: Invoice?
    @State private var errorMessage = ""
    @State private var isGenerating = false
    @State private var customCustomerName = ""
    @State private var customSignerName = ""
    @State private var customLineDescription = "Loan signing"
    @State private var customLineAmount = ""

    private var customers: [CustomerSummary] {
        CustomerSummaries.build(from: appState.orders)
            .filter { !$0.invoiceCandidates.isEmpty }
    }

    private var selectedCustomer: CustomerSummary? {
        guard let selectedCustomerID else { return customers.first }
        return customers.first { $0.id == selectedCustomerID }
    }

    var body: some View {
        ZStack {
            ParchmentBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: NLSpacing.lg) {
                    ScreenTitleBlock(title: "Invoices", subtitle: "Generate customer invoices and PDFs from unpaid signing work.")
                    ErrorBanner(message: errorMessage)

                    if customers.isEmpty {
                        EmptyStateView(title: "No invoice candidates", systemImage: "doc.richtext", message: "Unpaid, non-cancelled signing orders will appear here.")
                        customInvoiceCard
                    } else {
                        NLCard {
                            VStack(alignment: .leading, spacing: NLSpacing.md) {
                                Text("Customer")
                                    .font(.headline)
                                    .foregroundColor(NLColor.navy)
                        Picker("Customer", selection: Binding(
                            get: { selectedCustomerID ?? customers.first?.id ?? "" },
                            set: { selectedCustomerID = $0 }
                        )) {
                            ForEach(customers) { customer in
                                Text(customer.displayName).tag(customer.id)
                            }
                        }
                                .pickerStyle(.menu)
                                .tint(NLColor.navy)
                            }
                    }

                    if let selectedCustomer {
                            NLCard {
                                VStack(alignment: .leading, spacing: NLSpacing.md) {
                                    Text("Customer / Signer Details")
                                        .font(.headline)
                                        .foregroundColor(NLColor.navy)
                                    DetailRow(label: "Customer", value: selectedCustomer.displayName)
                                    DetailRow(label: "Signing count", value: "\(selectedCustomer.signingCount)")
                                    DetailRow(label: "Unpaid work", value: "\(selectedCustomer.unpaidCount)")
                                }
                            }

                            VStack(alignment: .leading, spacing: NLSpacing.md) {
                                SectionHeader(title: "Line Items")
                            ForEach(selectedCustomer.invoiceCandidates) { order in
                                    NLCard {
                                        VStack(alignment: .leading, spacing: NLSpacing.sm) {
                                            HStack {
                                                Text(order.signerName)
                                                    .font(.subheadline.weight(.semibold))
                                                    .foregroundColor(NLColor.ink)
                                                Spacer()
                                                Text(order.fee.currencyString)
                                                    .font(.subheadline.weight(.bold))
                                                    .foregroundColor(NLColor.navy)
                                            }
                                            DetailRow(label: "Date", value: order.displayDate)
                                            DetailRow(label: "Type", value: order.signingType ?? "Signing")
                                        }
                                    }
                                }
                                NLCard {
                                    DetailRow(label: "Balance", value: selectedCustomer.invoiceCandidates.reduce(0) { $0 + $1.fee }.currencyString)
                                }
                            }

                            Button(isGenerating ? "Generating..." : "Generate Invoice PDF") {
                                Task { await generateInvoice(for: selectedCustomer) }
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(isGenerating)
                        }
                    }

                if let generatedInvoice {
                        NLCard {
                            VStack(alignment: .leading, spacing: NLSpacing.md) {
                                Text("Generated Invoice")
                                    .font(.headline)
                                    .foregroundColor(NLColor.navy)
                                DetailRow(label: "Invoice", value: generatedInvoice.invoiceNumber)
                                DetailRow(label: "Payer", value: generatedInvoice.payerName)
                                DetailRow(label: "Balance", value: generatedInvoice.balanceDue.currencyString)
                                if let pdfURL = generatedInvoice.pdfURL, let url = URL(string: pdfURL) {
                                    Link("Open PDF", destination: url)
                                }
                            }
                        }
                    }
                }
                .padding(NLSpacing.lg)
            }
        }
        .onAppear {
            selectedCustomerID = selectedCustomerID ?? customers.first?.id
        }
    }

    private var customInvoiceCard: some View {
        NLCard {
            VStack(alignment: .leading, spacing: NLSpacing.md) {
                Text("Custom Invoice Generator")
                    .font(.headline)
                    .foregroundColor(NLColor.navy)
                NLTextField(title: "Customer name", text: $customCustomerName)
                NLTextField(title: "Signer details", text: $customSignerName)
                NLTextField(title: "Line item", text: $customLineDescription)
                NLTextField(title: "Amount", text: $customLineAmount, keyboardType: .decimalPad)
                BannerView(kind: .info, message: "Custom invoice PDFs require a saved signing order before generation.")
            }
        }
    }

    private func generateInvoice(for customer: CustomerSummary) async {
        errorMessage = ""
        isGenerating = true
        defer { isGenerating = false }

        let request = InvoiceRequest(
            customerName: customer.displayName,
            orderIds: customer.invoiceCandidates.map(\.id)
        )

        do {
            generatedInvoice = try await APIService.shared.requestInvoice(request)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

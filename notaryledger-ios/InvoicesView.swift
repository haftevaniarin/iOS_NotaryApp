import SwiftUI

struct InvoicesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedCustomerID: String?
    @State private var generatedInvoice: Invoice?
    @State private var errorMessage = ""
    @State private var isGenerating = false

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
            List {
                if !errorMessage.isEmpty {
                    Section {
                        ErrorBanner(message: errorMessage)
                    }
                    .listRowBackground(Color.clear)
                }

                if customers.isEmpty {
                    Section {
                        EmptyStateView(title: "No invoice candidates", systemImage: "doc.richtext", message: "Unpaid, non-cancelled signing orders will appear here.")
                    }
                    .listRowBackground(Color.clear)
                } else {
                    Section("Customer") {
                        Picker("Customer", selection: Binding(
                            get: { selectedCustomerID ?? customers.first?.id ?? "" },
                            set: { selectedCustomerID = $0 }
                        )) {
                            ForEach(customers) { customer in
                                Text(customer.displayName).tag(customer.id)
                            }
                        }
                    }

                    if let selectedCustomer {
                        Section("Line Items") {
                            ForEach(selectedCustomer.invoiceCandidates) { order in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(order.signerName)
                                            .font(.subheadline.weight(.semibold))
                                        Text(order.displayDate)
                                            .font(.caption)
                                            .foregroundColor(NLColor.muted)
                                    }
                                    Spacer()
                                    Text(order.fee.currencyString)
                                        .foregroundColor(NLColor.navy)
                                }
                            }
                            HStack {
                                Text("Balance")
                                    .fontWeight(.semibold)
                                Spacer()
                                Text(selectedCustomer.invoiceCandidates.reduce(0) { $0 + $1.fee }.currencyString)
                                    .fontWeight(.bold)
                                    .foregroundColor(NLColor.navy)
                            }
                        }

                        Section {
                            Button(isGenerating ? "Generating..." : "Generate Invoice PDF") {
                                Task { await generateInvoice(for: selectedCustomer) }
                            }
                            .disabled(isGenerating)
                        }
                    }
                }

                if let generatedInvoice {
                    Section("Generated Invoice") {
                        DetailRow(label: "Invoice", value: generatedInvoice.invoiceNumber)
                        DetailRow(label: "Payer", value: generatedInvoice.payerName)
                        DetailRow(label: "Balance", value: generatedInvoice.balanceDue.currencyString)
                        if let pdfURL = generatedInvoice.pdfURL, let url = URL(string: pdfURL) {
                            Link("Open PDF", destination: url)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Invoices")
        .onAppear {
            selectedCustomerID = selectedCustomerID ?? customers.first?.id
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

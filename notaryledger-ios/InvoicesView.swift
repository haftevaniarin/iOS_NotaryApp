import SwiftUI

struct InvoicesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedCustomerID: String?
    @State private var exportItem: ShareURL?
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
                    } else {
                        NLCard {
                            VStack(alignment: .leading, spacing: NLSpacing.md) {
                                Text("Customer")
                                    .font(NLTypography.cardTitle)
                                    .foregroundColor(NLColor.navy)
                        NLSelectField(title: "Customer", selection: Binding(
                            get: { selectedCustomerID ?? customers.first?.id ?? "" },
                            set: { selectedCustomerID = $0 }
                        ), value: selectedCustomer?.displayName ?? "Select customer") {
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
                                        .font(NLTypography.cardTitle)
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
                                                    .font(NLTypography.bodyStrong)
                                                    .foregroundColor(NLColor.ink)
                                                Spacer()
                                                Text(order.fee.currencyString)
                                                    .font(NLFonts.mono(13.5, weight: .semibold))
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

                    customInvoiceCard
                }
                .nlScreenPadding()
            }
        }
        .sheet(item: $exportItem) { ShareSheet(activityItems: [$0.url]) }
        .onAppear {
            selectedCustomerID = selectedCustomerID ?? customers.first?.id
        }
    }

    private var customInvoiceCard: some View {
        NLCard {
            VStack(alignment: .leading, spacing: NLSpacing.md) {
                Text("Custom Invoice Generator")
                    .font(NLTypography.cardTitle)
                    .foregroundColor(NLColor.navy)
                NLTextField(title: "Customer name", text: $customCustomerName)
                NLTextField(title: "Signer details", text: $customSignerName)
                NLTextField(title: "Line item", text: $customLineDescription)
                NLTextField(title: "Amount", text: $customLineAmount, keyboardType: .decimalPad)
                Button("Generate Custom Invoice PDF") { Task { await generateCustom() } }.buttonStyle(PrimaryButtonStyle()).disabled(isGenerating)
            }
        }
    }

    private func generateInvoice(for customer: CustomerSummary) async {
        errorMessage = ""
        isGenerating = true
        defer { isGenerating = false }

        do {
            try await requireInvoiceAccess()
            exportItem = ShareURL(url: try LedgerPDF.invoice(user: appState.currentUser, customer: customer.displayName, orders: customer.invoiceCandidates))
        } catch { errorMessage = error.localizedDescription }
    }
    private func requireInvoiceAccess() async throws {
        let billing = try await APIService.shared.fetchBillingStatus()
        guard billing.features?["invoiceGeneration"] == true else { throw APIError.serverError("Upgrade to Pro to generate invoices.") }
    }
    private func generateCustom() async {
        errorMessage = ""
        guard !customCustomerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !customLineDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let amount = Double(customLineAmount), amount.isFinite, amount >= 0 else { errorMessage = "Enter a customer, service description, and valid amount."; return }
        isGenerating = true
        defer { isGenerating = false }
        do {
            try await requireInvoiceAccess()
            let description = customLineDescription + (customSignerName.isEmpty ? "" : " for " + customSignerName)
            exportItem = ShareURL(url: try LedgerPDF.invoice(user: appState.currentUser, customer: customCustomerName, orders: [], customDescription: description, customAmount: amount))
        } catch { errorMessage = error.localizedDescription }
    }
}

import SwiftUI

struct CustomersView: View {
    @EnvironmentObject private var appState: AppState
    @State private var searchText = ""

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
                            CustomerSummaryCard(summary: summary)
                        }
                    }
                }
                .padding(NLSpacing.lg)
            }
        }
    }
}

struct CustomerSummaryCard: View {
    let summary: CustomerSummary

    var body: some View {
        NLCard {
            VStack(alignment: .leading, spacing: NLSpacing.md) {
                HStack(alignment: .top) {
                    Text(summary.displayName)
                        .font(.headline)
                        .foregroundColor(NLColor.ink)
                    Spacer()
                    Text(summary.revenue.currencyString)
                        .font(.headline)
                        .foregroundColor(NLColor.navy)
                }
                DetailRow(label: "Latest signing", value: summary.orders.first?.displayDate ?? "-")
                DetailRow(label: "Signing count", value: "\(summary.signingCount)")
                DetailRow(label: "Unpaid work", value: "\(summary.unpaidCount)")
                DetailRow(label: "Revenue", value: summary.revenue.currencyString)
                if summary.invoiceCandidates.isEmpty {
                    Button {
                    } label: {
                        Label("No Invoice Due", systemImage: "doc.richtext")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(true)
                } else {
                    Button {
                    } label: {
                        Label("Create Invoice", systemImage: "doc.richtext")
                    }
                    .buttonStyle(PrimaryButtonStyle())
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

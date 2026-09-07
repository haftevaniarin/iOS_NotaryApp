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
            List {
                if summaries.isEmpty {
                    Section {
                        EmptyStateView(title: "No customers found", systemImage: "person.2", message: "Customers are derived from signing history.")
                    }
                    .listRowBackground(Color.clear)
                } else {
                    Section("Customers") {
                        ForEach(summaries) { summary in
                            NavigationLink {
                                CustomerDetailView(summary: summary)
                            } label: {
                                CustomerSummaryRow(summary: summary)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .searchable(text: $searchText, prompt: "Search customers")
        }
        .navigationTitle("Customers")
    }
}

struct CustomerSummaryRow: View {
    let summary: CustomerSummary

    var body: some View {
        VStack(alignment: .leading, spacing: NLSpacing.sm) {
            HStack {
                Text(summary.displayName)
                    .font(.headline)
                    .foregroundColor(NLColor.ink)
                Spacer()
                Text(summary.revenue.currencyString)
                    .font(.headline)
                    .foregroundColor(NLColor.navy)
            }
            HStack(spacing: NLSpacing.md) {
                Label("\(summary.signingCount)", systemImage: "doc.text")
                Label("\(summary.unpaidCount)", systemImage: "clock")
                Label("\(summary.invoiceCandidates.count)", systemImage: "doc.richtext")
            }
            .font(.caption)
            .foregroundColor(NLColor.muted)
        }
        .padding(.vertical, 6)
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

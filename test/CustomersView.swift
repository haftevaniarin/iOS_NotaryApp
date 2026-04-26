import SwiftUI

struct CustomerSummary: Identifiable {
    let id: String // normalized name
    let displayName: String
    let orderCount: Int
    let paidCount: Int
    let unpaidCount: Int
    let totalFees: Double
    let orders: [SigningOrder]
}

struct CustomersView: View {
    let orders: [SigningOrder]

    private var summaries: [CustomerSummary] {
        let groups = Dictionary(grouping: orders) { (order: SigningOrder) -> String in
            order.customerName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }

        return groups.map { key, orders in
            let paid = orders.filter { $0.paid }
            let unpaid = orders.filter { !$0.paid }
            return CustomerSummary(
                id: key,
                displayName: orders.first?.customerName ?? key,
                orderCount: orders.count,
                paidCount: paid.count,
                unpaidCount: unpaid.count,
                totalFees: orders.reduce(0) { $0 + $1.fee },
                orders: orders
            )
        }
        .sorted { $0.displayName < $1.displayName }
    }

    var body: some View {
        List {
            ForEach(summaries) { s in
                NavigationLink {
                    CustomerDetailView(summary: s)
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(s.displayName)
                                .font(.headline)
                            Text("Orders: \(s.orderCount) • Paid: \(s.paidCount) • Unpaid: \(s.unpaidCount)")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }

                        Spacer()

                        Text("$" + String(format: "%.2f", s.totalFees))
                            .fontWeight(.semibold)
                    }
                }
            }
        }
        .navigationTitle("Customers")
    }
}

struct CustomerDetailView: View {
    let summary: CustomerSummary

    var body: some View {
        List {
            Section("Summary") {
                Text("Total Orders: \(summary.orderCount)")
                Text("Paid: \(summary.paidCount)")
                Text("Unpaid: \(summary.unpaidCount)")
                Text("Total Fees: $" + String(format: "%.2f", summary.totalFees))
            }

            Section("Orders") {
                ForEach(summary.orders) { order in
                    VStack(alignment: .leading) {
                        Text(order.customerName).font(.headline)
                        Text(order.displayDate).font(.subheadline).foregroundColor(.gray)
                        Text("$" + String(format: "%.2f", order.fee)).fontWeight(.semibold)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .navigationTitle(summary.displayName)
    }
}

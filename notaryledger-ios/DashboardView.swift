import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showAddOrder = false

    private var metrics: DashboardMetrics {
        FinancialSummary.dashboardMetrics(orders: appState.orders)
    }

    private var upcomingSignings: [SigningOrder] {
        let today = Calendar.current.startOfDay(for: Date())
        return appState.orders
            .filter { order in
                guard !order.isCancelled, let date = DateParser.date(from: order.date) else { return false }
                return date >= today && order.normalizedStatus != .paid
            }
            .sorted { $0.date < $1.date }
            .prefix(5)
            .map { $0 }
    }

    private var travelMileageTotal: Double {
        appState.orders.reduce(0) { $0 + ($1.mileage ?? 0) }
    }

    private var travelFeeTotal: Double {
        appState.orders.reduce(0) { $0 + ($1.travelFee ?? 0) }
    }

    private var todaySubtitle: String {
        Formatters.displayDate.string(from: Date())
    }

    var body: some View {
        ZStack {
            ParchmentBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: NLSpacing.lg) {
                    ScreenTitleBlock(title: "Dashboard", subtitle: todaySubtitle)

                    if appState.isLoading {
                        ProgressView("Loading ledger...")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    }

                    ErrorBanner(message: appState.errorMessage)
                    CredentialRiskBanners()

                    Button {
                        showAddOrder = true
                    } label: {
                        ActionPill(title: "New Signing", systemImage: "plus")
                    }

                    UpcomingSigningsSection(orders: upcomingSignings)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: NLSpacing.md)], spacing: NLSpacing.md) {
                        MetricCard(title: "Signings", value: "\(metrics.ytdSigningOrderCount)", systemImage: "doc.text")
                        MetricCard(title: "Monthly Revenue", value: metrics.monthRevenue.currencyString, systemImage: "dollarsign.circle")
                        MetricCard(title: "Fees Earned", value: metrics.feesEarned.currencyString, systemImage: "checkmark.seal")
                        MetricCard(title: "Pending Payment", value: metrics.pendingPayment.currencyString, systemImage: "clock")
                        MetricCard(title: "Average Fee", value: metrics.averageFeePerSigning.currencyString, systemImage: "chart.line.uptrend.xyaxis")
                    }

                    TravelTotalsSection(mileage: travelMileageTotal, travelFees: travelFeeTotal)
                    RecentActivitySection(orders: Array(appState.orders.prefix(8)))
                }
                .padding(NLSpacing.lg)
            }
            .refreshable {
                await appState.refreshAll()
            }
        }
        .sheet(isPresented: $showAddOrder) {
            NavigationStack {
                SigningOrderFormView(order: nil) { payload in
                    let created = try await APIService.shared.createOrder(payload)
                    await MainActor.run {
                        appState.upsertOrder(created)
                    }
                }
            }
        }
    }

}

struct CredentialRiskBanners: View {
    var body: some View {
        VStack(spacing: NLSpacing.sm) {
            BannerView(kind: .warning, message: "Review commission expiration, bond, E&O insurance, and notary credential details in Profile.")
        }
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: NLSpacing.sm) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundColor(NLColor.brass)
                Spacer()
            }
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundColor(NLColor.navy)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(title)
                .font(.caption)
                .foregroundColor(NLColor.muted)
        }
        .frame(maxWidth: .infinity, minHeight: 98, alignment: .leading)
        .nlPanel()
    }
}

struct TravelTotalsSection: View {
    let mileage: Double
    let travelFees: Double

    var body: some View {
        VStack(alignment: .leading, spacing: NLSpacing.md) {
            Text("Travel Totals")
                .font(.headline)
                .foregroundColor(NLColor.navy)

            NLCard {
                VStack(spacing: NLSpacing.md) {
                    DetailRow(label: "Mileage", value: String(format: "%.1f mi", mileage))
                    DetailRow(label: "Travel fees", value: travelFees.currencyString)
                    DetailRow(label: "IRS mileage note", value: "Track business miles before tax export.")
                }
            }
        }
    }
}

struct UpcomingSigningsSection: View {
    let orders: [SigningOrder]

    var body: some View {
        VStack(alignment: .leading, spacing: NLSpacing.md) {
            Text("Upcoming Signings")
                .font(.headline)
                .foregroundColor(NLColor.navy)

            if orders.isEmpty {
                EmptyStateView(title: "No upcoming signings", systemImage: "calendar.badge.checkmark", message: "Scheduled signings will appear here first on iPhone.")
            } else {
                VStack(spacing: 0) {
                    ForEach(orders) { order in
                        SigningOrderCompactRow(order: order)
                        if order.id != orders.last?.id {
                            Divider()
                        }
                    }
                }
                .nlPanel()
            }
        }
    }
}

struct RecentActivitySection: View {
    let orders: [SigningOrder]

    var body: some View {
        VStack(alignment: .leading, spacing: NLSpacing.md) {
            Text("Recent Activity")
                .font(.headline)
                .foregroundColor(NLColor.navy)
            if orders.isEmpty {
                EmptyStateView(title: "No signing orders", systemImage: "tray", message: "Create a signing order to start your ledger.")
            } else {
                VStack(spacing: 0) {
                    ForEach(orders) { order in
                        SigningOrderCompactRow(order: order)
                        if order.id != orders.last?.id {
                            Divider()
                        }
                    }
                }
                .nlPanel()
            }
        }
    }
}

struct SigningOrderCompactRow: View {
    let order: SigningOrder

    var body: some View {
        HStack(alignment: .top, spacing: NLSpacing.md) {
            VStack(alignment: .leading, spacing: NLSpacing.xs) {
                Text(order.customerName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(NLColor.ink)
                    .lineLimit(1)
                Text(order.signerName)
                    .font(.caption)
                    .foregroundColor(NLColor.muted)
                Text([order.displayDate, order.time].compactMap { $0 }.joined(separator: " at "))
                    .font(.caption)
                    .foregroundColor(NLColor.muted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: NLSpacing.xs) {
                Text(order.fee.currencyString)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(NLColor.navy)
                StatusBadge(status: order.normalizedStatus)
            }
        }
        .padding(.vertical, 10)
    }
}

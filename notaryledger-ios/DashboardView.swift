import SwiftUI

struct DashboardView: View {
    @Environment(\.nlViewportWidth) private var width
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
        appState.orders.filter(\.countsInFinancialTotals).reduce(0) { $0 + ($1.mileage ?? 0) }
    }

    private var travelFeeTotal: Double {
        appState.orders.filter(\.countsInFinancialTotals).reduce(0) { $0 + ($1.travelFee ?? 0) }
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

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: NLLayout.metricColumns(for: width)), spacing: 16) {
                        MetricCard(title: "Signings", value: "\(metrics.ytdSigningOrderCount)", systemImage: "doc.text")
                        MetricCard(title: "Monthly Revenue", value: metrics.monthRevenue.currencyString, systemImage: "dollarsign.circle")
                        MetricCard(title: "Fees Earned", value: metrics.feesEarned.currencyString, systemImage: "checkmark.seal")
                        MetricCard(title: "Pending Payment", value: metrics.pendingPayment.currencyString, systemImage: "clock")
                        MetricCard(title: "Average Fee", value: metrics.averageFeePerSigning.currencyString, systemImage: "chart.line.uptrend.xyaxis")
                    }

                    TravelTotalsSection(mileage: travelMileageTotal, travelFees: travelFeeTotal)
                    RecentActivitySection(orders: Array(appState.orders.prefix(8)))
                }
                .nlScreenPadding()
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
    @State private var credentials: Credentials?
    @State private var error = ""
    private var risks: [(String, String)] {
        guard let credentials else { return [] }
        let items: [(String, String?)] = [
            ("Commission", credentials.commissionExpirationDate),
            ("E&O insurance", credentials.eoExpirationDate),
            ("Background check", credentials.backgroundCheckExpirationDate),
            (credentials.certificationName ?? "Certification", credentials.certificationExpirationDate)
        ]
        return items.compactMap { label, date in
            guard let date, !date.isEmpty else { return nil }
            let status = CredentialsEditor.expirationStatus(date)
            return status == "Current" ? nil : (label, status)
        }
    }
    var body: some View {
        VStack(spacing: NLSpacing.sm) {
            ErrorBanner(message: error)
            ForEach(risks.indices, id: \.self) { i in
                BannerView(kind: risks[i].1 == "Expired" ? .error : .warning, message: "\(risks[i].0): \(risks[i].1). Update your credentials in Profile.")
            }
        }.task {
            do { credentials = try await APIService.shared.fetchCredentials() }
            catch { self.error = "Could not load credential reminders: " + error.localizedDescription }
        }
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title.uppercased())
                    .font(NLTypography.label)
                    .foregroundColor(NLColor.muted)
                Spacer()
                Image(systemName: systemImage)
                    .font(.system(size: 16))
                    .foregroundColor(NLColor.brass)
            }
            Text(value)
                .font(NLTypography.metric)
                .foregroundColor(NLColor.navy)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .nlPanel()
    }
}

struct TravelTotalsSection: View {
    let mileage: Double
    let travelFees: Double

    var body: some View {
        VStack(alignment: .leading, spacing: NLSpacing.md) {
            Text("Travel Totals")
                .font(NLTypography.cardTitle)
                .foregroundColor(NLColor.navy)

            NLCard {
                VStack(spacing: NLSpacing.md) {
                    DetailRow(label: "Mileage", value: String(format: "%.1f mi", mileage))
                    DetailRow(label: "Parking and tolls", value: travelFees.currencyString)
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
                .font(NLTypography.cardTitle)
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
                .font(NLTypography.cardTitle)
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
                    .font(NLTypography.bodyStrong)
                    .foregroundColor(NLColor.ink)
                    .lineLimit(1)
                Text(order.signerName)
                    .font(NLTypography.caption)
                    .foregroundColor(NLColor.muted)
                Text([order.displayDate, order.time].compactMap { $0 }.joined(separator: " at "))
                    .font(NLTypography.caption)
                    .foregroundColor(NLColor.muted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: NLSpacing.xs) {
                Text(order.fee.currencyString)
                    .font(NLTypography.bodyStrong)
                    .foregroundColor(NLColor.navy)
                StatusBadge(status: order.normalizedStatus)
            }
        }
        .padding(.vertical, 10)
    }
}

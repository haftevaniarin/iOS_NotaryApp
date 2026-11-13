import SwiftUI

// This adapter reads the ledger already in memory. It adds no dashboard API calls.
struct LedgerDashboardHost: View {
    @ObservedObject var appState: AppState
    @State private var model: DashboardViewModel
    @State private var destination: DashboardRoute?
    @Environment(\.openURL) private var openURL
    init(appState: AppState) {
        self.appState = appState
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--dashboard-design-fixtures") {
            _model = State(initialValue: PreviewData.loadedModel)
            return
        }
        #endif
        let repository = InMemoryDashboardRepository { LedgerDashboardSnapshot.make(orders: appState.orders, expenses: appState.expenses) }
        let model = DashboardViewModel(repository: repository); model.loadsOnAppear = false
        _model = State(initialValue: model)
    }
    var body: some View {
        DashboardView(model: model, onRoute: { destination = $0 }, onNavigate: { signing in
            if let url = DashboardMaps.url(address: signing.address) { openURL(url) }
        }, onSeeAll: { appState.selectedSection = .signings })
            .task(id: LedgerDashboardRevision(orders: appState.orders, expenses: appState.expenses)) { await model.load() }
            .sheet(item: $destination) { route in
                switch route {
                case .signing:
                    NavigationStack {
                        SigningOrderFormView(order: nil) { payload in
                            let created = try await APIService.shared.createOrder(payload)
                            appState.upsertOrder(created)
                        }
                    }
                case .expense:
                    NavigationStack {
                        ExpenseFormView(expense: nil) { payload in
                            let created = try await APIService.shared.createExpense(payload)
                            appState.upsertExpense(created)
                        }
                    }
                default:
                    DashboardPlaceholderView(route: route)
                }
            }
    }
}

private struct LedgerDashboardRevision: Equatable { let orders: [SigningOrder]; let expenses: [Expense] }

struct DashboardPlaceholderView: View {
    let route: DashboardRoute
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: route.systemImage).font(.system(size: 32)).foregroundStyle(Color.brassText).accessibilityHidden(true)
                Text(route.title).font(DashboardTheme.heading(26))
                Text("This destination is ready for the next part of the app.")
                    .font(DashboardTheme.body(14)).foregroundStyle(Color.muted).multilineTextAlignment(.center)
            }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.parchment)
                .navigationTitle(route.title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.frame(minWidth: 44, minHeight: 44) } }
        }
    }
}

nonisolated enum DashboardMaps {
    static func url(address: String) -> URL? {
        guard !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        var components = URLComponents(); components.scheme = "https"; components.host = "maps.apple.com"
        components.queryItems = [URLQueryItem(name: "daddr", value: address), URLQueryItem(name: "dirflg", value: "d")]
        return components.url
    }
}

// Cash received for this month's signing dates less recorded business expenses and
// parking/tolls, consistent with the existing dashboard's signing-date grouping.
// No tax deductions or missing location/distance values are inferred here.
enum LedgerDashboardSnapshot {
    static func make(orders: [SigningOrder], expenses: [Expense], now: Date = Date(), calendar: Calendar = .current) -> DashboardSnapshot {
        let active = orders.filter(\.countsInFinancialTotals)
        let month = active.filter { contains($0.date, inMonthOf: now, calendar: calendar) }
        let previous = calendar.date(byAdding: .month, value: -1, to: now)
        let currentNet = net(orders: month, expenses: expenses, date: now, calendar: calendar)
        let previousOrders = active.filter { order in previous.map { contains(order.date, inMonthOf: $0, calendar: calendar) } ?? false }
        let previousNet = previous.map { net(orders: previousOrders, expenses: expenses, date: $0, calendar: calendar) } ?? 0
        let percent: Decimal? = previousNet > 0 ? (currentNet - previousNet) / previousNet * 100 : nil
        let monthExpenses = expenses.filter { contains($0.date, inMonthOf: now, calendar: calendar) }
        let businessExpenses = monthExpenses.reduce(Decimal.zero) { $0 + decimal($1.amount) * decimal($1.businessUsePercent) / 100 }
        let travel = month.reduce(Decimal.zero) { $0 + decimal($1.travelFee ?? 0) }
        let stats = MonthStats(netIncome: currentNet, signings: month.count,
                               mileage: month.reduce(Decimal.zero) { $0 + decimal($1.mileage ?? 0) },
                               expenses: businessExpenses + travel, netIncomeChangePercent: percent)
        let signings = active.compactMap { order -> Signing? in
            guard let start = OrderScheduleRules.timestamp(for: order) else { return nil }
            return Signing(id: order.id, signerName: order.signerName, loanType: order.signingType ?? "Signing",
                           address: address(order), startsAt: start, distanceMiles: order.mileageDetails?.oneWayMiles.map { decimal($0) }, fee: decimal(order.fee))
        }
        let unpaid = active.filter(\.isUnpaidCandidate)
        let attention: [AttentionItem] = unpaid.isEmpty ? [] : [AttentionItem(id: "unpaid", title: "\(unpaid.count) unpaid invoice\(unpaid.count == 1 ? "" : "s")",
            subtitle: "Review outstanding signing fees", systemImage: "doc.richtext", route: .unpaidInvoices)]
        return DashboardSnapshot(signings: signings, monthStats: stats, attentionItems: attention)
    }
    private static func decimal(_ value: Double) -> Decimal { Decimal(string: String(value), locale: Locale(identifier: "en_US_POSIX")) ?? 0 }
    private static func contains(_ value: String, inMonthOf date: Date, calendar: Calendar) -> Bool {
        guard let parsed = DateParser.date(from: value) else { return false }
        return calendar.isDate(parsed, equalTo: date, toGranularity: .month)
    }
    private static func net(orders: [SigningOrder], expenses: [Expense], date: Date, calendar: Calendar) -> Decimal {
        let earned = orders.filter(\.paid).reduce(Decimal.zero) { $0 + decimal($1.fee) }
        let costs = expenses.filter { contains($0.date, inMonthOf: date, calendar: calendar) }.reduce(Decimal.zero) { $0 + decimal($1.amount) * decimal($1.businessUsePercent) / 100 }
        return earned - costs - orders.reduce(Decimal.zero) { $0 + decimal($1.travelFee ?? 0) }
    }
    private static func address(_ order: SigningOrder) -> String {
        if let address = order.mileageDetails?.tripEndAddress, !address.isEmpty { return address }
        let prefix = "Signing location:"
        guard let line = order.notes?.components(separatedBy: .newlines).first(where: { $0.hasPrefix(prefix) }) else { return "" }
        return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
    }
}

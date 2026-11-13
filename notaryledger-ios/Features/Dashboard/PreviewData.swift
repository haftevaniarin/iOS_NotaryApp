import Foundation

// Synthetic values live here, never in production view bodies or ledger totals.
enum PreviewData {
    static let date = makeDate(day: 12, hour: 8, minute: 30)
    static let loaded = DashboardSnapshot(signings: [
        Signing(id: "preview-next", signerName: "Nora James", loanType: "Refinance", address: "123 Example Ave, Los Angeles, CA", startsAt: makeDate(day: 12, hour: 10, minute: 30), distanceMiles: 8, fee: 175),
        Signing(id: "preview-2", signerName: "Daniel & Mia Chen", loanType: "Buyer package", address: "100 Grand Ave, Los Angeles, CA", startsAt: makeDate(day: 13, hour: 9), distanceMiles: 12, fee: 200),
        Signing(id: "preview-3", signerName: "Olivia Martinez", loanType: "HELOC", address: "200 Lake Ave, Pasadena, CA", startsAt: makeDate(day: 14, hour: 14), distanceMiles: 16, fee: 150),
        Signing(id: "preview-4", signerName: "Ethan Williams", loanType: "Seller package", address: "300 Colorado Blvd, Pasadena, CA", startsAt: makeDate(day: 16, hour: 11), distanceMiles: 10, fee: 125)
    ], monthStats: MonthStats(netIncome: 4280, signings: 24, mileage: 186, expenses: 642, netIncomeChangePercent: 12), attentionItems: [
        AttentionItem(id: "commission", title: "Commission expires soon", subtitle: "Renew within the next 30 days", systemImage: "checkmark.seal", route: .credentials),
        AttentionItem(id: "invoices", title: "3 invoices need a follow-up", subtitle: "Review your outstanding signing fees", systemImage: "doc.richtext", route: .unpaidInvoices)
    ])
    static let empty = DashboardSnapshot(signings: [], monthStats: .zero, attentionItems: [])
    static let loading = loaded
    static var loadingNext: Signing? { loading.signings.first }
    static var loadingUpcoming: [Signing] { Array(loading.signings.dropFirst().prefix(3)) }
    static var loadedModel: DashboardViewModel { .preview(snapshot: loaded, date: date) }
    static var emptyModel: DashboardViewModel { .preview(snapshot: empty, date: date) }
    static var loadingModel: DashboardViewModel { .preview(snapshot: loading, date: date, state: .loading) }
    static var errorModel: DashboardViewModel { .preview(snapshot: empty, date: date, state: .error("Dashboard information could not be loaded. Please try again.")) }
    private static func makeDate(day: Int, hour: Int, minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .current
        return calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute)) ?? Date(timeIntervalSince1970: 0)
    }
}

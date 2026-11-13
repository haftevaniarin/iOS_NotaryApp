import Foundation

nonisolated struct Signing: Identifiable, Equatable, Sendable {
    let id: String
    let signerName: String
    let loanType: String
    let address: String
    let startsAt: Date
    let distanceMiles: Decimal?
    let fee: Decimal
    var currencyCode = "USD"
}

nonisolated enum DashboardRoute: Hashable, Identifiable, Sendable {
    case signing, journal, expense, mileage, notifications, signingFile(Signing.ID)
    case credentials, unpaidInvoices
    var id: String {
        switch self {
        case .signing: "signing"
        case .journal: "journal"
        case .expense: "expense"
        case .mileage: "mileage"
        case .notifications: "notifications"
        case .signingFile(let id): "file-\(id)"
        case .credentials: "credentials"
        case .unpaidInvoices: "unpaid-invoices"
        }
    }
    var title: String {
        switch self {
        case .signing: "Add signing"
        case .journal: "Journal"
        case .expense: "Add expense"
        case .mileage: "Mileage"
        case .notifications: "Notifications"
        case .signingFile: "Signing file"
        case .credentials: "Credentials"
        case .unpaidInvoices: "Unpaid invoices"
        }
    }
    var systemImage: String {
        switch self {
        case .signing: "plus"
        case .journal: "book.closed"
        case .expense: "receipt"
        case .mileage: "car"
        case .notifications: "bell"
        case .signingFile: "doc.text"
        case .credentials: "checkmark.seal"
        case .unpaidInvoices: "doc.richtext"
        }
    }
}

nonisolated struct AttentionItem: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let route: DashboardRoute
}

nonisolated struct MonthStats: Equatable, Sendable {
    let netIncome: Decimal
    let signings: Int
    let mileage: Decimal
    let expenses: Decimal
    let netIncomeChangePercent: Decimal?
    var currencyCode = "USD"
    static let zero = MonthStats(netIncome: 0, signings: 0, mileage: 0, expenses: 0, netIncomeChangePercent: nil)
}

nonisolated struct DashboardSnapshot: Equatable, Sendable {
    let signings: [Signing]
    let monthStats: MonthStats
    let attentionItems: [AttentionItem]
    static let empty = DashboardSnapshot(signings: [], monthStats: .zero, attentionItems: [])
}

import Foundation

struct SignupRequest: Codable {
    let fullName: String
    let email: String
    let password: String
}

struct LoginRequest: Codable {
    let email: String
    let password: String
}

struct AuthUser: Codable, Equatable {
    let id: String
    var fullName: String
    var email: String
    var firstName: String?
    var lastName: String?
    var role: String?
    var isAdmin: Bool?

    var displayFirstName: String {
        firstName ?? fullName.split(separator: " ").first.map(String.init) ?? ""
    }

    var displayLastName: String {
        if let lastName {
            return lastName
        }
        let pieces = fullName.split(separator: " ").map(String.init)
        return pieces.dropFirst().joined(separator: " ")
    }

    var canAccessAdminAudit: Bool {
        isAdmin == true || role?.localizedCaseInsensitiveContains("admin") == true
    }
}

struct AuthResponse: Decodable {
    let token: String
    let refreshToken: String?
    let user: AuthUser

    enum CodingKeys: String, CodingKey {
        case token
        case accessToken
        case refreshToken
        case user
    }

    init(token: String, refreshToken: String? = nil, user: AuthUser) {
        self.token = token
        self.refreshToken = refreshToken
        self.user = user
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        token = try container.decodeIfPresent(String.self, forKey: .token)
            ?? container.decode(String.self, forKey: .accessToken)
        refreshToken = try container.decodeIfPresent(String.self, forKey: .refreshToken)
        user = try container.decode(AuthUser.self, forKey: .user)
    }
}

enum SigningStatus: String, Codable, CaseIterable, Identifiable {
    case scheduled = "Scheduled"
    case pending = "Pending"
    case overdue = "Overdue"
    case paid = "Paid"
    case cancelled = "Cancelled"

    var id: String { rawValue }

    init(normalizing value: String?) {
        switch value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "paid":
            self = .paid
        case "cancelled", "canceled":
            self = .cancelled
        case "overdue":
            self = .overdue
        case "pending", "pending payment", "unpaid":
            self = .pending
        default:
            self = .scheduled
        }
    }
}

struct SigningOrder: Decodable, Identifiable, Equatable {
    let id: String
    var customerName: String
    var payerName: String?
    var signerName: String
    var signingType: String?
    var date: String
    var time: String?
    var fee: Double
    var notarialActFee: Double
    var paid: Bool
    var paidDate: String?
    var invoiceNumber: String
    var notes: String?
    var mileage: Double?
    var travelFee: Double?
    var status: SigningStatus?
    var userId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case mongoId = "_id"
        case customerName
        case payerName
        case signerName
        case signingType
        case date
        case time
        case fee
        case notarialActFee
        case paid
        case paidDate
        case invoiceNumber
        case notes
        case mileage
        case miles
        case travelFee
        case status
        case paymentStatus
        case userId
    }

    init(
        id: String,
        customerName: String,
        payerName: String? = nil,
        signerName: String,
        signingType: String? = nil,
        date: String,
        time: String? = nil,
        fee: Double,
        notarialActFee: Double = 0,
        paid: Bool,
        paidDate: String? = nil,
        invoiceNumber: String = "",
        notes: String? = nil,
        mileage: Double? = nil,
        travelFee: Double? = nil,
        status: SigningStatus? = nil,
        userId: String? = nil
    ) {
        self.id = id
        self.customerName = customerName
        self.payerName = payerName
        self.signerName = signerName
        self.signingType = signingType
        self.date = date
        self.time = time
        self.fee = fee
        self.notarialActFee = notarialActFee
        self.paid = paid
        self.paidDate = paidDate
        self.invoiceNumber = invoiceNumber
        self.notes = notes
        self.mileage = mileage
        self.travelFee = travelFee
        self.status = status
        self.userId = userId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decodeIfPresent(String.self, forKey: .mongoId)
            ?? UUID().uuidString
        customerName = try container.decodeIfPresent(String.self, forKey: .customerName) ?? ""
        payerName = try container.decodeIfPresent(String.self, forKey: .payerName)
        signerName = try container.decodeIfPresent(String.self, forKey: .signerName) ?? ""
        signingType = try container.decodeIfPresent(String.self, forKey: .signingType)
        date = try container.decodeIfPresent(String.self, forKey: .date) ?? ""
        time = try container.decodeIfPresent(String.self, forKey: .time)
        fee = try container.decodeFlexibleDouble(forKey: .fee) ?? 0
        notarialActFee = try container.decodeFlexibleDouble(forKey: .notarialActFee) ?? 0
        paid = try container.decodeIfPresent(Bool.self, forKey: .paid) ?? false
        paidDate = try container.decodeIfPresent(String.self, forKey: .paidDate)
        invoiceNumber = try container.decodeIfPresent(String.self, forKey: .invoiceNumber) ?? ""
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        mileage = try container.decodeFlexibleDouble(forKey: .mileage)
            ?? container.decodeFlexibleDoubleIfPresent(forKey: .miles)
        travelFee = try container.decodeFlexibleDouble(forKey: .travelFee)
        let rawStatus = try container.decodeIfPresent(String.self, forKey: .status)
            ?? container.decodeIfPresent(String.self, forKey: .paymentStatus)
        status = rawStatus == nil ? nil : SigningStatus(normalizing: rawStatus)
        userId = try container.decodeIfPresent(String.self, forKey: .userId)
    }

    var displayDate: String {
        guard let parsed = DateParser.date(from: date) else { return date }
        return Formatters.displayDate.string(from: parsed)
    }

    var normalizedStatus: SigningStatus {
        if let status, status == .cancelled {
            return .cancelled
        }
        if paid {
            return .paid
        }
        if let status, status != .paid {
            return status
        }
        guard let signingDate = DateParser.date(from: date) else {
            return .scheduled
        }
        return signingDate < Calendar.current.startOfDay(for: Date()) ? .overdue : .scheduled
    }

    var isCancelled: Bool {
        normalizedStatus == .cancelled
    }

    var isUnpaidCandidate: Bool {
        !paid && !isCancelled
    }

    var countsInFinancialTotals: Bool {
        !isCancelled
    }

    var payerDisplayName: String {
        let payer = payerName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return payer?.isEmpty == false ? payer! : customerName
    }
}

struct SigningOrderPayload: Codable, Equatable {
    var customerName: String
    var payerName: String?
    var signerName: String
    var signingType: String?
    var date: String
    var time: String?
    var fee: Double
    var notarialActFee: Double
    var paid: Bool
    var paidDate: String?
    var invoiceNumber: String
    var notes: String?
    var mileage: Double?
    var travelFee: Double?
    var status: SigningStatus

    enum CodingKeys: String, CodingKey {
        case customerName
        case payerName
        case signerName
        case signingType
        case date
        case time
        case fee
        case notarialActFee
        case paid
        case paidDate
        case invoiceNumber
        case notes
        case mileage
        case travelFee
        case status
    }

    init(
        customerName: String,
        payerName: String?,
        signerName: String,
        signingType: String?,
        date: String,
        time: String?,
        fee: Double,
        notarialActFee: Double,
        paid: Bool,
        paidDate: String?,
        invoiceNumber: String,
        notes: String?,
        mileage: Double?,
        travelFee: Double?,
        status: SigningStatus
    ) {
        self.customerName = customerName
        self.payerName = payerName
        self.signerName = signerName
        self.signingType = signingType
        self.date = date
        self.time = time
        self.fee = fee
        self.notarialActFee = notarialActFee
        self.paid = status == .cancelled ? false : paid
        self.paidDate = status == .cancelled ? nil : paidDate
        self.invoiceNumber = invoiceNumber
        self.notes = notes
        self.mileage = mileage
        self.travelFee = travelFee
        self.status = status
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(customerName, forKey: .customerName)
        try container.encodeIfPresent(payerName, forKey: .payerName)
        try container.encode(signerName, forKey: .signerName)
        try container.encodeIfPresent(signingType, forKey: .signingType)
        try container.encode(date, forKey: .date)
        try container.encodeIfPresent(time, forKey: .time)
        try container.encode(fee, forKey: .fee)
        try container.encode(notarialActFee, forKey: .notarialActFee)
        try container.encode(paid, forKey: .paid)
        if let paidDate {
            try container.encode(paidDate, forKey: .paidDate)
        } else {
            try container.encodeNil(forKey: .paidDate)
        }
        try container.encode(invoiceNumber, forKey: .invoiceNumber)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encodeIfPresent(mileage, forKey: .mileage)
        try container.encodeIfPresent(travelFee, forKey: .travelFee)
        try container.encode(status.rawValue, forKey: .status)
    }
}

struct Expense: Decodable, Identifiable, Equatable {
    let id: String
    var date: String
    var category: String
    var description: String
    var amount: Double
    var businessUsePercent: Double
    var receiptURL: String?

    enum CodingKeys: String, CodingKey {
        case id
        case mongoId = "_id"
        case date
        case category
        case description
        case amount
        case businessUsePercent
        case receiptURL
    }

    init(id: String, date: String, category: String, description: String, amount: Double, businessUsePercent: Double, receiptURL: String? = nil) {
        self.id = id
        self.date = date
        self.category = category
        self.description = description
        self.amount = amount
        self.businessUsePercent = businessUsePercent
        self.receiptURL = receiptURL
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decodeIfPresent(String.self, forKey: .mongoId)
            ?? UUID().uuidString
        date = try container.decodeIfPresent(String.self, forKey: .date) ?? ""
        category = try container.decodeIfPresent(String.self, forKey: .category) ?? ""
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        amount = try container.decodeFlexibleDouble(forKey: .amount) ?? 0
        businessUsePercent = try container.decodeFlexibleDouble(forKey: .businessUsePercent) ?? 100
        receiptURL = try container.decodeIfPresent(String.self, forKey: .receiptURL)
    }
}

struct ExpensePayload: Codable, Equatable {
    var date: String
    var category: String
    var description: String
    var amount: Double
    var businessUsePercent: Double
}

struct CustomerSummary: Identifiable, Equatable {
    let id: String
    let displayName: String
    let signingCount: Int
    let unpaidCount: Int
    let revenue: Double
    let invoiceCandidates: [SigningOrder]
    let orders: [SigningOrder]
}

enum CustomerSummaries {
    static func build(from orders: [SigningOrder]) -> [CustomerSummary] {
        let groups = Dictionary(grouping: orders) { order in
            order.customerName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }

        return groups.map { key, groupedOrders in
            let activeOrders = groupedOrders.filter(\.countsInFinancialTotals)
            return CustomerSummary(
                id: key,
                displayName: groupedOrders.first?.customerName ?? key,
                signingCount: groupedOrders.count,
                unpaidCount: activeOrders.filter(\.isUnpaidCandidate).count,
                revenue: activeOrders.filter(\.paid).reduce(0) { $0 + $1.fee },
                invoiceCandidates: activeOrders.filter(\.isUnpaidCandidate),
                orders: groupedOrders.sorted { $0.date > $1.date }
            )
        }
        .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }
}

struct InvoiceLineItem: Codable, Identifiable, Equatable {
    var id: String
    var description: String
    var amount: Double
}

struct Invoice: Codable, Identifiable, Equatable {
    let id: String
    var invoiceNumber: String
    var payerName: String
    var customerName: String?
    var lineItems: [InvoiceLineItem]
    var balanceDue: Double
    var pdfURL: String?
}

struct InvoiceRequest: Codable, Equatable {
    var customerName: String
    var orderIds: [String]
}

struct TaxSummary: Codable, Equatable {
    var taxYear: Int
    var incomeReceived: Double
    var unpaidIncome: Double
    var businessExpenses: Double
    var travelExpenses: Double
    var notarialActFeeExemptPortion: Double
    var netSelfEmploymentIncome: Double
    var selfEmploymentTaxableIncome: Double
    var estimatedSelfEmploymentTax: Double
    var estimatedTaxPayments: Double
}

struct SupportContactRequest: Codable, Equatable {
    var name: String
    var email: String
    var topic: String
    var subject: String
    var message: String
    var sourcePage: String
}

struct MaintenanceStatus: Decodable, Equatable {
    var enabled: Bool
    var title: String?
    var message: String?

    static let disabled = MaintenanceStatus(enabled: false, title: nil, message: nil)

    enum CodingKeys: String, CodingKey {
        case enabled
        case maintenance
        case isMaintenanceMode
        case title
        case message
    }

    init(enabled: Bool, title: String?, message: String?) {
        self.enabled = enabled
        self.title = title
        self.message = message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled)
            ?? container.decodeIfPresent(Bool.self, forKey: .maintenance)
            ?? container.decodeIfPresent(Bool.self, forKey: .isMaintenanceMode)
            ?? false
        title = try container.decodeIfPresent(String.self, forKey: .title)
        message = try container.decodeIfPresent(String.self, forKey: .message)
    }
}

enum PasswordValidation {
    static func message(for password: String) -> String? {
        if password.count < 12 {
            return "Use at least 12 characters."
        }
        if password.count > 128 {
            return "Use 128 characters or fewer."
        }
        if password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Password cannot be only whitespace."
        }

        var categories = 0
        if password.range(of: "[a-z]", options: .regularExpression) != nil { categories += 1 }
        if password.range(of: "[A-Z]", options: .regularExpression) != nil { categories += 1 }
        if password.range(of: "[0-9]", options: .regularExpression) != nil { categories += 1 }
        if password.range(of: "[^A-Za-z0-9]", options: .regularExpression) != nil { categories += 1 }

        return categories >= 3 ? nil : "Use at least 3 of lowercase, uppercase, number, and symbol."
    }
}

enum FinancialSummary {
    static func dashboardMetrics(orders: [SigningOrder], now: Date = Date()) -> DashboardMetrics {
        let active = orders.filter(\.countsInFinancialTotals)
        let calendar = Calendar.current
        let month = calendar.component(.month, from: now)
        let year = calendar.component(.year, from: now)

        let monthOrders = active.filter { order in
            guard let date = DateParser.date(from: order.date) else { return false }
            return calendar.component(.month, from: date) == month && calendar.component(.year, from: date) == year
        }
        let ytdOrders = orders.filter { order in
            guard let date = DateParser.date(from: order.date) else { return false }
            return calendar.component(.year, from: date) == year
        }
        let paidThisMonth = monthOrders.filter(\.paid)
        let feesEarned = paidThisMonth.reduce(0) { $0 + $1.fee }

        return DashboardMetrics(
            monthRevenue: feesEarned,
            feesEarned: feesEarned,
            pendingPayment: monthOrders.filter(\.isUnpaidCandidate).reduce(0) { $0 + $1.fee },
            averageFeePerSigning: monthOrders.isEmpty ? 0 : monthOrders.reduce(0) { $0 + $1.fee } / Double(monthOrders.count),
            ytdSigningOrderCount: ytdOrders.count
        )
    }

    static func localTaxSummary(orders: [SigningOrder], expenses: [Expense], year: Int) -> TaxSummary {
        let activeOrders = orders.filter { order in
            guard order.countsInFinancialTotals, let date = DateParser.date(from: order.date) else { return false }
            return Calendar.current.component(.year, from: date) == year
        }
        let yearExpenses = expenses.filter { expense in
            guard let date = DateParser.date(from: expense.date) else { return false }
            return Calendar.current.component(.year, from: date) == year
        }
        let incomeReceived = activeOrders.filter(\.paid).reduce(0) { $0 + $1.fee }
        let unpaidIncome = activeOrders.filter(\.isUnpaidCandidate).reduce(0) { $0 + $1.fee }
        let businessExpenses = yearExpenses.reduce(0) { $0 + ($1.amount * ($1.businessUsePercent / 100)) }
        let travelExpenses = activeOrders.reduce(0) { $0 + ($1.travelFee ?? 0) }
        let exempt = activeOrders.reduce(0) { $0 + $1.notarialActFee }
        let net = max(0, incomeReceived - exempt - businessExpenses - travelExpenses)
        let taxable = net * 0.9235
        let seTax = taxable * 0.153

        return TaxSummary(
            taxYear: year,
            incomeReceived: incomeReceived,
            unpaidIncome: unpaidIncome,
            businessExpenses: businessExpenses,
            travelExpenses: travelExpenses,
            notarialActFeeExemptPortion: exempt,
            netSelfEmploymentIncome: net,
            selfEmploymentTaxableIncome: taxable,
            estimatedSelfEmploymentTax: seTax,
            estimatedTaxPayments: 0
        )
    }
}

struct DashboardMetrics: Equatable {
    var monthRevenue: Double
    var feesEarned: Double
    var pendingPayment: Double
    var averageFeePerSigning: Double
    var ytdSigningOrderCount: Int
}

enum DateParser {
    static func date(from value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        if let date = Formatters.apiDate.date(from: value) {
            return date
        }
        return ISO8601DateFormatter().date(from: value)
    }

    static func apiDateString(from date: Date) -> String {
        Formatters.apiDate.string(from: date)
    }
}

enum Formatters {
    static let apiDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static let displayDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateStyle = .medium
        return formatter
    }()

    static let currency: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 2
        return formatter
    }()
}

extension Double {
    var currencyString: String {
        Formatters.currency.string(from: NSNumber(value: self)) ?? "$\(String(format: "%.2f", self))"
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleDouble(forKey key: Key) throws -> Double? {
        if let value = try decodeIfPresent(Double.self, forKey: key) {
            return value
        }
        if let value = try decodeIfPresent(Int.self, forKey: key) {
            return Double(value)
        }
        if let value = try decodeIfPresent(String.self, forKey: key) {
            return Double(value)
        }
        return nil
    }

    func decodeFlexibleDoubleIfPresent(forKey key: Key) -> Double? {
        (try? decodeFlexibleDouble(forKey: key)) ?? nil
    }
}

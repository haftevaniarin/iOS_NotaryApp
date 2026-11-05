import Foundation

struct SignupRequest: Codable {
    let firstName: String
    let lastName: String
    let email: String
    let password: String
}

struct LoginRequest: Codable {
    let email: String
    let password: String
    var clientType = "native"
}

struct AuthUser: Codable, Equatable {
    let id: String
    var fullName: String
    var email: String
    var firstName: String?
    var lastName: String?
    var role: String?
    var isAdmin: Bool?
    var defaultStartAddress: String?
    var profilePhotoUrl: String?
    var profilePhotoUpload: PhotoUpload?

    var displayFirstName: String {
        firstName ?? fullName.split(separator: " ").first.map { String($0) } ?? ""
    }

    var displayLastName: String {
        if let lastName {
            return lastName
        }
        let pieces = fullName.split(separator: " ").map { String($0) }
        return pieces.dropFirst().joined(separator: " ")
    }

    var canAccessAdminAudit: Bool {
        role?.uppercased() == "ADMIN"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case mongoId = "_id"
        case fullName
        case name
        case email
        case firstName
        case lastName
        case role
        case isAdmin, defaultStartAddress, profilePhotoUrl, profilePhotoUpload
    }

    init(
        id: String,
        fullName: String,
        email: String,
        firstName: String? = nil,
        lastName: String? = nil,
        role: String? = nil,
        isAdmin: Bool? = nil
    ) {
        self.id = id
        self.fullName = fullName
        self.email = email
        self.firstName = firstName
        self.lastName = lastName
        self.role = role
        self.isAdmin = isAdmin
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decode(String.self, forKey: .mongoId)
        email = try container.decodeIfPresent(String.self, forKey: .email) ?? ""
        firstName = try container.decodeIfPresent(String.self, forKey: .firstName)
        lastName = try container.decodeIfPresent(String.self, forKey: .lastName)
        let decodedFullName = try container.decodeIfPresent(String.self, forKey: .fullName)
            ?? container.decodeIfPresent(String.self, forKey: .name)
        fullName = decodedFullName
            ?? [firstName, lastName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        role = try container.decodeIfPresent(String.self, forKey: .role)
        isAdmin = try container.decodeIfPresent(Bool.self, forKey: .isAdmin)
        defaultStartAddress = try container.decodeIfPresent(String.self, forKey: .defaultStartAddress)
        profilePhotoUrl = try container.decodeIfPresent(String.self, forKey: .profilePhotoUrl)
        profilePhotoUpload = try container.decodeIfPresent(PhotoUpload.self, forKey: .profilePhotoUpload)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(fullName, forKey: .fullName)
        try container.encode(email, forKey: .email)
        try container.encodeIfPresent(firstName, forKey: .firstName)
        try container.encodeIfPresent(lastName, forKey: .lastName)
        try container.encodeIfPresent(role, forKey: .role)
        try container.encodeIfPresent(isAdmin, forKey: .isAdmin)
        try container.encodeIfPresent(defaultStartAddress, forKey: .defaultStartAddress)
        try container.encodeIfPresent(profilePhotoUrl, forKey: .profilePhotoUrl)
        try container.encodeIfPresent(profilePhotoUpload, forKey: .profilePhotoUpload)
    }
}

struct AuthResponse: Decodable {
    let token: String
    let user: AuthUser?
    var refreshToken: String? = nil

    enum CodingKeys: String, CodingKey {
        case token
        case accessToken
        case refreshToken
        case user
    }

    init(token: String, user: AuthUser? = nil) {
        self.token = token
        self.user = user
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        token = try container.decodeIfPresent(String.self, forKey: .token)
            ?? container.decode(String.self, forKey: .accessToken)
        user = try container.decodeIfPresent(AuthUser.self, forKey: .user)
        refreshToken = try container.decodeIfPresent(String.self, forKey: .refreshToken)
    }
}

enum RegistrationResult {
    case authenticated(AuthResponse)
    case verificationRequired(String)
}

struct RegistrationResponse: Decodable {
    struct Payload: Decodable {
        let refreshToken: String?
        let token: String?
        let accessToken: String?
        let user: AuthUser?
        let message: String?
        let emailVerificationRequired: Bool?
        let requiresEmailVerification: Bool?
        let verificationRequired: Bool?
    }

    let refreshToken: String?
    let token: String?
    let accessToken: String?
    let user: AuthUser?
    let message: String?
    let code: String?
    let emailVerificationRequired: Bool?
    let requiresEmailVerification: Bool?
    let verificationRequired: Bool?
    let data: Payload?

    var result: RegistrationResult? {
        let requiresVerification = data?.emailVerificationRequired == true
            || data?.requiresEmailVerification == true || data?.verificationRequired == true
            || emailVerificationRequired == true || requiresEmailVerification == true
            || verificationRequired == true || code == "EMAIL_VERIFICATION_REQUIRED"
        let resolvedToken = data?.accessToken ?? data?.token ?? accessToken ?? token
        let resolvedUser = data?.user ?? user
        if !requiresVerification, let resolvedToken, !resolvedToken.isEmpty, let resolvedUser {
            var response = AuthResponse(token: resolvedToken, user: resolvedUser)
            response.refreshToken = data?.refreshToken ?? refreshToken
            return .authenticated(response)
        }
        return .verificationRequired(data?.message ?? message ?? AuthCopy.verifyAccount)
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
    var mileageDetails: OrderMileage?

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
            ?? container.decode(String.self, forKey: .mongoId)
        customerName = try container.decodeIfPresent(String.self, forKey: .customerName) ?? ""
        payerName = try container.decodeIfPresent(String.self, forKey: .payerName)
        signerName = try container.decodeIfPresent(String.self, forKey: .signerName) ?? ""
        signingType = try container.decodeIfPresent(String.self, forKey: .signingType)
        date = try container.decodeIfPresent(String.self, forKey: .date) ?? ""
        time = try container.decodeIfPresent(String.self, forKey: .time)
        if time == nil, date.contains("T"), let scheduled = DateParser.date(from: date) {
            let clock = DateFormatter(); clock.locale = Locale(identifier: "en_US_POSIX"); clock.dateFormat = "HH:mm"
            time = clock.string(from: scheduled)
        }
        fee = try container.decodeFlexibleDouble(forKey: .fee) ?? 0
        notarialActFee = try container.decodeFlexibleDouble(forKey: .notarialActFee) ?? 0
        paid = try container.decodeIfPresent(Bool.self, forKey: .paid) ?? false
        paidDate = try container.decodeIfPresent(String.self, forKey: .paidDate)
        invoiceNumber = try container.decodeIfPresent(String.self, forKey: .invoiceNumber) ?? ""
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        mileageDetails = try? container.decodeIfPresent(OrderMileage.self, forKey: .mileage)
        mileage = mileageDetails?.businessMiles ?? container.decodeFlexibleDoubleIfPresent(forKey: .mileage)
            ?? container.decodeFlexibleDoubleIfPresent(forKey: .miles)
        travelFee = mileageDetails?.parkingFee ?? container.decodeFlexibleDoubleIfPresent(forKey: .travelFee)
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

struct SigningOrderPayload: Encodable, Equatable {
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
    var preserveMileage = false

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
        case mileage = "miles"
        case travelFee = "parkingFee"
        case status = "paymentStatus"
        case oneWayMiles, mileageTripType, mileageEntryMode
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
        self.paidDate = paid && status != .cancelled ? paidDate : nil
        self.invoiceNumber = invoiceNumber
        self.notes = notes
        self.mileage = mileage
        self.travelFee = travelFee
        self.status = status == .cancelled ? .cancelled : paid ? .paid : status == .paid ? .pending : status
    }

    static func scheduledDate(date: String, time: String?) -> String {
        guard let time, !time.isEmpty, let day = DateParser.date(from: date) else { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        guard let clock = formatter.date(from: time) else { return date }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: clock)
        guard let scheduled = Calendar.current.date(bySettingHour: parts.hour ?? 0, minute: parts.minute ?? 0, second: 0, of: day) else { return date }
        return ISO8601DateFormatter().string(from: scheduled)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(customerName, forKey: .customerName)
        try container.encode(payerName, forKey: .payerName)
        try container.encode(signerName, forKey: .signerName)
        try container.encode(signingType, forKey: .signingType)
        try container.encode(Self.scheduledDate(date: date, time: time), forKey: .date)
        try container.encode(fee, forKey: .fee)
        try container.encode(notarialActFee, forKey: .notarialActFee)
        try container.encode(paid, forKey: .paid)
        if let paidDate {
            try container.encode(paidDate, forKey: .paidDate)
        } else {
            try container.encodeNil(forKey: .paidDate)
        }
        try container.encode(invoiceNumber, forKey: .invoiceNumber)
        try container.encode(notes, forKey: .notes)
        if !preserveMileage {
            try container.encode(mileage, forKey: .mileage)
            try container.encode(mileage, forKey: .oneWayMiles)
            try container.encode(mileage == nil ? nil : "ONE_WAY", forKey: .mileageTripType)
            try container.encode(mileage == nil ? nil : "MANUAL", forKey: .mileageEntryMode)
            try container.encode(travelFee, forKey: .travelFee)
        }
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
            ?? container.decode(String.self, forKey: .mongoId)
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

struct MileagePayload: Codable, Equatable {
    var mileage: Double?
    var travelFee: Double?
    enum CodingKeys: String, CodingKey { case mileage = "miles", travelFee = "parkingFee" }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(mileage, forKey: .mileage)
        try c.encode(travelFee, forKey: .travelFee)
    }
}

struct Credentials: Codable, Equatable {
    var commissionNumber: String? = nil
    var commissionState: String? = nil
    var commissionStartDate: String? = nil
    var commissionExpirationDate: String? = nil
    var eoProvider: String? = nil
    var eoPolicyNumber: String? = nil
    var eoCoverageAmount: String? = nil
    var eoStartDate: String? = nil
    var eoExpirationDate: String? = nil
    var certificationName: String? = nil
    var certificationExpirationDate: String? = nil
    var backgroundCheckProvider: String? = nil
    var backgroundCheckCompletedDate: String? = nil
    var backgroundCheckExpirationDate: String? = nil
    init() {}
    enum CodingKeys: String, CodingKey { case commissionNumber, commissionState, commissionStartDate, commissionExpirationDate, eoProvider, eoPolicyNumber, eoCoverageAmount, eoStartDate, eoExpirationDate, certificationName, certificationExpirationDate, backgroundCheckProvider, backgroundCheckCompletedDate, backgroundCheckExpirationDate }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard c.contains(.commissionNumber) || c.contains(.backgroundCheckProvider) else { throw APIError.invalidResponse }
        commissionNumber = try c.decodeIfPresent(String.self, forKey: .commissionNumber)
        commissionState = try c.decodeIfPresent(String.self, forKey: .commissionState)
        commissionStartDate = try c.decodeIfPresent(String.self, forKey: .commissionStartDate)
        commissionExpirationDate = try c.decodeIfPresent(String.self, forKey: .commissionExpirationDate)
        eoProvider = try c.decodeIfPresent(String.self, forKey: .eoProvider)
        eoPolicyNumber = try c.decodeIfPresent(String.self, forKey: .eoPolicyNumber)
        eoCoverageAmount = (try? c.decode(String.self, forKey: .eoCoverageAmount)) ?? (try? c.decode(Double.self, forKey: .eoCoverageAmount)).map { String($0) }
        eoStartDate = try c.decodeIfPresent(String.self, forKey: .eoStartDate)
        eoExpirationDate = try c.decodeIfPresent(String.self, forKey: .eoExpirationDate)
        certificationName = try c.decodeIfPresent(String.self, forKey: .certificationName)
        certificationExpirationDate = try c.decodeIfPresent(String.self, forKey: .certificationExpirationDate)
        backgroundCheckProvider = try c.decodeIfPresent(String.self, forKey: .backgroundCheckProvider)
        backgroundCheckCompletedDate = try c.decodeIfPresent(String.self, forKey: .backgroundCheckCompletedDate)
        backgroundCheckExpirationDate = try c.decodeIfPresent(String.self, forKey: .backgroundCheckExpirationDate)
    }
    func requestBody() throws -> Data {
        var object: [String: Any] = [:]
        object["commissionNumber"] = commissionNumber?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? NSNull()
        object["commissionState"] = commissionState?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? NSNull()
        object["commissionStartDate"] = commissionStartDate?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? NSNull()
        object["commissionExpirationDate"] = commissionExpirationDate?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? NSNull()
        object["eoProvider"] = eoProvider?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? NSNull()
        object["eoPolicyNumber"] = eoPolicyNumber?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? NSNull()
        if let value = eoCoverageAmount?.nilIfEmpty {
            guard let number = Double(value), number.isFinite, number >= 0 else { throw APIError.serverError("Enter a valid E&O coverage amount.") }
            object["eoCoverageAmount"] = number
        } else { object["eoCoverageAmount"] = NSNull() }
        object["eoStartDate"] = eoStartDate?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? NSNull()
        object["eoExpirationDate"] = eoExpirationDate?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? NSNull()
        object["certificationName"] = certificationName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? NSNull()
        object["certificationExpirationDate"] = certificationExpirationDate?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? NSNull()
        object["backgroundCheckProvider"] = backgroundCheckProvider?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? NSNull()
        object["backgroundCheckCompletedDate"] = backgroundCheckCompletedDate?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? NSNull()
        object["backgroundCheckExpirationDate"] = backgroundCheckExpirationDate?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? NSNull()
        return try JSONSerialization.data(withJSONObject: object)
    }
}

typealias CredentialsPayload = Credentials

struct BillingStatusPayload: Codable, Equatable {
    var plan: String?
    var subscriptionStatus: String?
    var billingInterval: String?
    var isPro: Bool?
    var cancelAtPeriodEnd: Bool?
    var currentPeriodEnd: String?
    var remainingFreeOrders: Int?
    var features: [String: Bool]?
    var scheduledChange: ScheduledBillingChange?
}
struct ScheduledBillingChange: Codable, Equatable {
    var billingInterval: String?
    var effectiveAt: String?
}

struct BillingSession: Codable, Equatable {
    var url: String?
    var sessionId: String?
    enum CodingKeys: String, CodingKey { case url; case sessionId = "id" }
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
    var totalBusinessMiles: Double = 0
}

struct SupportContactRequest: Codable, Equatable {
    var name: String
    var email: String
    var topic: String
    var subject: String
    var message: String
    var sourcePage: String
}

nonisolated struct MaintenanceStatus: Decodable, Equatable {
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
        let categories = ["[a-z]", "[A-Z]", "[0-9]", "[^A-Za-z0-9\\s]"].filter {
            password.range(of: $0, options: .regularExpression) != nil
        }.count
        return password.utf16.count >= 12 && password.utf16.count <= 128
            && !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && categories >= 3
            ? nil : AuthCopy.passwordRequirements
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

enum TimeParser {
    static func date(from value: String?) -> Date? {
        guard let value else { return nil }
        let clock = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let patterns = [
            ("HH:mm", #"^([01][0-9]|2[0-3]):[0-5][0-9]$"#),
            ("h:mm a", #"^(0?[1-9]|1[0-2]):[0-5][0-9] [AP]M$"#)
        ]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.isLenient = false
        for (format, pattern) in patterns where clock.range(of: pattern, options: .regularExpression) != nil {
            formatter.dateFormat = format
            if let date = formatter.date(from: clock) { return date }
        }
        return nil
    }

    static func apiTimeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    static func normalized(_ value: String?) -> String {
        guard let date = date(from: value) else { return value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
        return apiTimeString(from: date)
    }
}

enum DateParser {
    static func date(from value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        if let date = Formatters.apiDate.date(from: value) {
            return date
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.date(from: value) ?? ISO8601DateFormatter().date(from: value)
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
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return Double(value)
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Double(value)
        }
        return nil
    }

    func decodeFlexibleDoubleIfPresent(forKey key: Key) -> Double? {
        (try? decodeFlexibleDouble(forKey: key)) ?? nil
    }
}

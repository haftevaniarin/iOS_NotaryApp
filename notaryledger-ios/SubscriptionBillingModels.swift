import Foundation

nonisolated struct SubscriptionPrice: Decodable, Equatable {
    let name: String
    let amountMinor: Int
    let currency: String
    let billingInterval: String
    var display: String { SubscriptionFormatting.money(amountMinor, currency: currency) + (billingInterval == "annual" ? " / year" : " / month") }
}
nonisolated enum SubscriptionFormatting {
    static func money(_ amount: Int, currency: String) -> String {
        let zero = ["bif", "clp", "djf", "gnf", "jpy", "kmf", "krw", "mga", "pyg", "rwf", "ugx", "vnd", "vuv", "xaf", "xof", "xpf"]
        let three = ["bhd", "jod", "kwd", "omr", "tnd"]
        let digits = zero.contains(currency.lowercased()) ? 0 : three.contains(currency.lowercased()) ? 3 : 2
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency.uppercased()
        formatter.minimumFractionDigits = digits; formatter.maximumFractionDigits = digits
        return formatter.string(from: NSNumber(value: Double(amount) / pow(10, Double(digits)))) ?? "\(amount) \(currency.uppercased())"
    }
    static func date(_ text: String?) -> String {
        guard let text else { return "Not available" }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = parser.date(from: text) ?? ISO8601DateFormatter().date(from: text) else { return "Not available" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
    static func trustedURL(_ value: String?) -> URL? {
        guard let value, let parts = URLComponents(string: value), parts.scheme == "https",
              parts.user == nil, parts.password == nil, parts.port == nil || parts.port == 443,
              let host = parts.host?.lowercased(), host == "stripe.com" || host.hasSuffix(".stripe.com")
                || host == "notaryledger.org" || host.hasSuffix(".notaryledger.org") else { return nil }
        return parts.url
    }
}
nonisolated struct SubscriptionPlan: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
    let price: SubscriptionPrice?
    let features: [String]
}
nonisolated struct SubscriptionCard: Decodable, Equatable {
    let brand: String
    let last4: String
    let expMonth: Int
    let expYear: Int
}
nonisolated struct SubscriptionAddress: Decodable, Equatable {
    let line1: String?
    let line2: String?
    let city: String?
    let state: String?
    let postalCode: String?
    let country: String?
    enum CodingKeys: String, CodingKey { case line1, line2, city, state, country; case postalCode = "postal_code" }
    var display: String { [line1, line2, city, state, postalCode, country].compactMap { value in value.flatMap { $0.isEmpty ? nil : $0 } }.joined(separator: ", ") }
}
nonisolated struct SubscriptionCustomer: Decodable, Equatable {
    let name: String?
    let email: String?
    let address: SubscriptionAddress?
}
nonisolated struct SubscriptionCapabilities: Decodable, Equatable {
    let manage: Bool
    let paymentMethod: Bool
    let billingDetails: Bool
    let cancel: Bool
    let resume: Bool
    let history: Bool
}
nonisolated struct SubscriptionPaymentIssue: Decodable, Equatable {
    let code: String
    let message: String
    let url: String?
}
nonisolated struct SubscriptionCharge: Decodable, Identifiable, Equatable {
    let id: String
    let number: String?
    let date: String?
    let status: String?
    let amountMinor: Int
    let paidMinor: Int
    let currency: String
    let receiptURL: String?
    let paymentURL: String?
}
nonisolated struct SubscriptionHistory: Decodable, Equatable {
    var items: [SubscriptionCharge]
    var nextCursor: String?
}
struct SubscriptionAccount: Decodable, Equatable {
    let billing: BillingStatusPayload
    let provider: String
    let plans: [SubscriptionPlan]
    let currentPrice: SubscriptionPrice?
    let currentPlanID: String?
    let hasSubscription: Bool
    let trialEnd: String?
    let renewalDate: String?
    let cancellationDate: String?
    let pendingUpdate: Bool
    let card: SubscriptionCard?
    let billingDetails: SubscriptionCustomer?
    let capabilities: SubscriptionCapabilities
    let paymentIssue: SubscriptionPaymentIssue?
    let history: SubscriptionHistory
}
nonisolated struct SubscriptionIntervalPreview: Decodable, Equatable, Identifiable {
    let billingInterval: String
    let targetPrice: SubscriptionPrice
    let effectiveAt: String
    let amountDueNowMinor: Int
    let prorationBehavior: String
    let expectedCurrentPeriodEnd: String
    let expectedAmountMinor: Int
    let expectedCurrency: String
    var id: String { billingInterval + effectiveAt + String(expectedAmountMinor) }
}
struct SubscriptionAccountResponse: Decodable { let account: SubscriptionAccount }
nonisolated struct SubscriptionHistoryResponse: Decodable { let history: SubscriptionHistory }
nonisolated struct SubscriptionPreviewResponse: Decodable { let preview: SubscriptionIntervalPreview }

nonisolated struct SubscriptionIntervalRequest: Encodable {
    let billingInterval: String
    let expectedCurrentPeriodEnd: String?
    let expectedAmountMinor: Int?
    let expectedCurrency: String?
}

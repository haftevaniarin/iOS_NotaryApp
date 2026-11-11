import Foundation

nonisolated enum BillingInterval: String, CaseIterable, Identifiable, Codable {
    case annual, monthly
    var id: String { rawValue }
    var title: String { self == .annual ? "Annual" : "Monthly" }
    var unit: String { self == .annual ? "year" : "month" }
}

nonisolated enum PlanTier: String, CaseIterable, Identifiable, Codable {
    case free, pro
    var id: String { rawValue }
    var definition: PlanDefinition { PlanCatalog.plans.first { $0.tier == self }! }
}
nonisolated struct PlanDefinition: Identifiable {
    let tier: PlanTier
    let name: String
    let featureLine: String
    var id: PlanTier { tier }
}
nonisolated enum PlanCatalog {
    // Copy matches the web billing page. All paid prices come from the backend.
    static let freeOrderLimit = 20
    static let proName = "Pro"
    static let plans = [
        PlanDefinition(tier: .free, name: "Free", featureLine: "\(freeOrderLimit) lifetime signing orders."),
        PlanDefinition(tier: .pro, name: "NotaryLedger Pro", featureLine: "Unlimited orders, invoices, tax reports, OCR, expense tools, and full reporting.")
    ]
    static func savings(monthly: Decimal, annual: Decimal) -> Int? {
        guard monthly > 0, annual > 0, annual < monthly * 12 else { return nil }
        return max(0, min(99, Int(NSDecimalNumber(decimal: (1 - annual / (monthly * 12)) * 100).doubleValue.rounded())))
    }
}

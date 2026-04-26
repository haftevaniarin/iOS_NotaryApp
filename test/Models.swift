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

struct AuthUser: Codable {
    let id: String
    let fullName: String
    let email: String
}

struct AuthResponse: Codable {
    let token: String
    let user: AuthUser
}

struct SigningOrder: Codable, Identifiable, Equatable {
    let id: String
    var customerName: String
    var signerName: String
    var date: String
    var fee: Double
    var paid: Bool
    var invoiceNumber: String
    var userId: String?
}

extension SigningOrder {
    /// Returns a user-friendly display date like "Apr 26, 2026".
    var displayDate: String {
        // Expecting yyyy-MM-dd from API; fallback to ISO8601 parsing and finally current date
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        if let d = formatter.date(from: date) {
            let out = DateFormatter()
            out.locale = Locale(identifier: "en_US")
            out.dateFormat = "MMM d, yyyy"
            return out.string(from: d)
        }

        // Try ISO8601
        if let iso = ISO8601DateFormatter().date(from: date) {
            let out = DateFormatter()
            out.locale = Locale(identifier: "en_US")
            out.dateFormat = "MMM d, yyyy"
            return out.string(from: iso)
        }

        return date
    }
}

struct SigningOrderRequest: Codable {
    let customerName: String
    let signerName: String
    let date: String
    let fee: Double
    let paid: Bool
    let invoiceNumber: String
}

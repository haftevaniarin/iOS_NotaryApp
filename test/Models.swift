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

struct SigningOrderRequest: Codable {
    let customerName: String
    let signerName: String
    let date: String
    let fee: Double
    let paid: Bool
    let invoiceNumber: String
}

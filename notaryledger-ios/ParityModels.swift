import Foundation

struct PhotoUpload: Codable, Equatable {
    var id: String
    var status: String
    var error: PhotoFailure?
    var isPending: Bool { ["SCANNING", "PROCESSING"].contains(status) }
}
struct PhotoFailure: Codable, Equatable { var code: String?; var message: String? }
struct PhotoResponse: Decodable {
    let profilePhotoUrl: String?
    let upload: PhotoUpload?
    enum CodingKeys: String, CodingKey { case profilePhotoUrl, upload }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard c.contains(.profilePhotoUrl) else { throw APIError.invalidResponse }
        profilePhotoUrl = try c.decodeIfPresent(String.self, forKey: .profilePhotoUrl)
        upload = try c.decodeIfPresent(PhotoUpload.self, forKey: .upload)
    }
}
struct DeletionStatus: Decodable {
    let deletionRequest: DeletionRequest?
}
struct DeletionRequest: Decodable {
    let id: String
    let status: String
    let requestedAt: String
    let scheduledDeletionAt: String?
    var isActive: Bool { ["PENDING", "IN_REVIEW"].contains(status) }
}
struct AuditPage: Decodable {
    let items: [AuditEntry]
    let pagination: Pagination
}
struct Pagination: Decodable { let page: Int; let pageSize: Int; let total: Int }
struct AuditEntry: Decodable, Identifiable {
    let id: String
    let action: String
    let actorUserId: String?
    let entityType: String?
    let entityId: String?
    let outcome: String
    let severity: String
    let createdAt: String
    let requestId: String?
}
struct OrderMileage: Codable, Equatable {
    var businessMiles: Double
    var oneWayMiles: Double?
    var roundTripMiles: Double?
    var parkingFee: Double
    var tripType: String?
    var entryMode: String?
    enum CodingKeys: String, CodingKey { case businessMiles, oneWayMiles, roundTripMiles, parkingFee, tripType, tripStartAddress, tripEndAddress; case entryMode = "mileageEntryMode" }
    var tripStartAddress: String?
    var tripEndAddress: String?
}
struct DistanceResponse: Decodable { let oneWayMiles: Double; let roundTripMiles: Double }
struct ExtractedSigning: Decodable, Identifiable {
    let id = UUID()
    var customerName: String?
    var payerName: String?
    var signerName: String?
    var signingType: String?
    var date: String?
    var time: String?
    var fee: Double?
    var invoiceNumber: String?
    var notes: String?
    enum CodingKeys: String, CodingKey { case customerName, payerName, signerName, signingType, date, time, fee, invoiceNumber, notes }
}

struct BusinessCard: Codable, Equatable {
    var slug: String? = nil
    var displayName: String? = nil
    var professionalTitle: String? = nil
    var businessName: String? = nil
    var bio: String? = nil
    var profilePhotoUrl: String? = nil
    var useProfilePhoto = false
    var logoUrl: String? = nil
    var businessPhone: String? = nil
    var businessEmail: String? = nil
    var websiteUrl: String? = nil
    var city: String? = nil
    var state: String? = nil
    var serviceAreas: [String] = []
    var languages: [String] = []
    var instagramUrl: String? = nil
    var facebookUrl: String? = nil
    var linkedinUrl: String? = nil
    var showBusinessPhone = false
    var showBusinessEmail = false
    var isPublished = false
    var canonicalUrl: String? = nil

    func updateBody() throws -> Data {
        let data = try JSONEncoder().encode(self)
        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        object.removeValue(forKey: "isPublished")
        object.removeValue(forKey: "canonicalUrl")
        // Null clears a saved optional field; omission would leave its old value.
        for key in ["displayName", "professionalTitle", "businessName", "bio", "profilePhotoUrl", "logoUrl", "businessPhone", "businessEmail", "websiteUrl", "city", "state", "instagramUrl", "facebookUrl", "linkedinUrl"] {
            if object[key] == nil || (object[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true { object[key] = NSNull() }
        }
        if (object["slug"] as? String)?.isEmpty == true { object.removeValue(forKey: "slug") }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}
struct CardResponse: Decodable { let card: BusinessCard }

struct BackendTaxSummary: Decodable {
    let taxYear: Int?
    let totals: Totals
    struct Totals: Decodable {
        let totalIncomeReceived: Double
        let unpaidIncome: Double
        let totalNotarialActExemptFees: Double
        let businessExpenses: Double
        let totalTravelExpenses: Double
        let totalBusinessMiles: Double
        let netSelfEmploymentIncome: Double
        let seTaxableIncome: Double
        let estimatedSelfEmploymentTax: Double
        let estimatedTaxPayments: Double
    }
    func summary(year: Int) -> TaxSummary {
        TaxSummary(taxYear: taxYear ?? year, incomeReceived: totals.totalIncomeReceived,
                   unpaidIncome: totals.unpaidIncome, businessExpenses: totals.businessExpenses,
                   travelExpenses: totals.totalTravelExpenses, notarialActFeeExemptPortion: totals.totalNotarialActExemptFees,
                   netSelfEmploymentIncome: totals.netSelfEmploymentIncome, selfEmploymentTaxableIncome: totals.seTaxableIncome,
                   estimatedSelfEmploymentTax: totals.estimatedSelfEmploymentTax, estimatedTaxPayments: totals.estimatedTaxPayments,
                   totalBusinessMiles: totals.totalBusinessMiles)
    }
}

enum UploadValidation {
    static func validate(data: Data, mimeType: String, photo: Bool) throws {
        let types = photo ? ["image/jpeg", "image/png", "image/webp"] : ["image/jpeg", "image/png", "image/webp", "application/pdf"]
        guard types.contains(mimeType) else { throw APIError.serverError(photo ? "Choose a JPEG, PNG, or WebP image." : "Choose a JPEG, PNG, WebP, or PDF file.") }
        guard !data.isEmpty, data.count <= (photo ? 5 : 10) * 1024 * 1024 else {
            throw APIError.serverError(photo ? "Choose an image of 5 MB or smaller." : "Choose a file of 10 MB or smaller.")
        }
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

struct ExtractedExpense: Decodable, Identifiable {
    let id = UUID()
    var description: String?
    var date: String?
    var amount: Double?
    var category: String?
    var businessUsePercent: Double?
    enum CodingKeys: String, CodingKey { case description, date, amount, category, businessUsePercent }
}
extension BusinessCard {
    func validationMessage() -> String? {
        if let slug, !slug.isEmpty {
            let reserved = Set(["admin", "api", "app", "auth", "account", "billing", "business-card", "card", "cards", "contact", "contact-vcf", "dashboard", "edit", "health", "help", "login", "logout", "me", "new", "notaryledger", "null", "orders", "preview", "privacy", "public", "publish", "register", "robots", "settings", "signup", "sitemap", "static", "support", "terms", "undefined", "unpublish", "www"])
            let value = slug.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !(3...64).contains(value.count) || value.range(of: #"^[a-z0-9]+(?:-[a-z0-9]+)*$"#, options: .regularExpression) == nil || reserved.contains(value) {
                return "Use a non-reserved URL slug of 3–64 letters, digits, and single hyphens."
            }
        }
        let text: [(String, String?, Int)] = [("Display name", displayName, 120), ("Professional title", professionalTitle, 120), ("Business name", businessName, 160), ("Bio", bio, 2000), ("City", city, 100), ("State", state, 100)]
        for (name, value, max) in text {
            guard let value else { continue }
            if value.count > max { return "\(name) must be \(max) characters or fewer." }
            let unsafe = name == "Bio" ? #"[<>\x00-\x09\x0B\x0C\x0E-\x1F\x7F-\x9F\u2028\u2029]"# : #"[<>\x00-\x1F\x7F-\x9F\u2028\u2029]"#
            if value.range(of: unsafe, options: .regularExpression) != nil { return "Use plain text for \(name.lowercased())." }
        }
        for (name, value, secure, hosts) in [
            ("Website", websiteUrl, false, [String]()), ("Photo", profilePhotoUrl, true, []), ("Logo", logoUrl, true, []),
            ("Instagram", instagramUrl, true, ["instagram.com", "www.instagram.com"]),
            ("Facebook", facebookUrl, true, ["facebook.com", "www.facebook.com"]),
            ("LinkedIn", linkedinUrl, true, ["linkedin.com", "www.linkedin.com"])
        ] {
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            guard value.count <= 2048, value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
                  !value.contains("\\"), !value.contains("<"), !value.contains(">"),
                  let url = URLComponents(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                  !secure || url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty,
                  url.user == nil, url.password == nil, hosts.isEmpty || hosts.contains(host.lowercased()) else {
                return "Enter a valid \(name.lowercased()) URL\(secure ? " using HTTPS" : "")."
            }
        }
        if let phone = businessPhone?.trimmingCharacters(in: .whitespacesAndNewlines), !phone.isEmpty {
            let digits = phone.filter(\.isNumber)
            let normalized = !phone.hasPrefix("+") && digits.count == 10 ? "1" + digits : digits
            if phone.count > 40 || phone.range(of: #"^\+?[0-9 ().-]+$"#, options: .regularExpression) == nil || !(8...15).contains(normalized.count) || normalized.first == "0" {
                return "Enter a phone number with 8–15 digits including the country code."
            }
        }
        if let email = businessEmail?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty,
           email.count > 254 || email.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) == nil { return "Enter a valid business email." }
        for (name, values, maxCount, maxLength) in [("service areas", serviceAreas, 30, 100), ("languages", languages, 20, 60)] {
            if values.count > maxCount || values.contains(where: { $0.count > maxLength || $0.range(of: #"[<>\x00-\x1F\x7F-\x9F]"#, options: .regularExpression) != nil }) { return "Enter up to \(maxCount) \(name), each up to \(maxLength) characters, using plain text." }
        }
        return nil
    }
}

struct EstimatedTaxPayment: Decodable, Identifiable {
    let id: String
    var date: String
    var amount: Double
    var quarter: String
    var taxYear: Int
    enum CodingKeys: String, CodingKey { case id, date, amount, quarter, taxYear }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        date = try c.decode(String.self, forKey: .date)
        if let value = try? c.decode(Double.self, forKey: .amount) { amount = value }
        else {
            guard let value = Double(try c.decode(String.self, forKey: .amount)), value.isFinite else { throw APIError.invalidResponse }
            amount = value
        }
        quarter = try c.decode(String.self, forKey: .quarter)
        taxYear = try c.decode(Int.self, forKey: .taxYear)
    }
}
struct EstimatedTaxPaymentPayload: Encodable {
    let date: String
    let amount: Double
    let quarter: String
    let taxYear: Int
}

struct SpreadsheetDraft: Identifiable {
    let id = UUID()
    let filename: String
    let mimeType: String
    var text: String
}
struct SigningImportResult: Decodable {
    let importedCount: Int
    let skippedDuplicateCount: Int
    let orders: [SigningOrder]
}

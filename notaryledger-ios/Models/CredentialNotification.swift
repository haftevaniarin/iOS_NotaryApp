import Foundation

struct CredentialNotification: Identifiable, Equatable {
    let id: CredentialSection
    let title: String
    let expirationDate: String
    let status: CredentialExpiration

    var message: String {
        switch status {
        case .expired: "Expired on \(expirationDate)"
        case .expiringSoon(days: 0): "Expires today"
        case .expiringSoon(let days): "Expires in \(days) days · \(expirationDate)"
        default: ""
        }
    }

    static func make(credentials: Credentials?, today: Date = Date(), calendar: Calendar = .current) -> [Self] {
        guard let credentials else { return [] }
        return CredentialSection.allCases.compactMap { section -> Self? in
            let expiration = credentials[keyPath: section.expirationKey]
            let status = CredentialDates.status(expiration, today: today, calendar: calendar)
            guard status.badgeTitle != nil else { return nil }
            let name = credentials.certificationName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            return Self(id: section, title: section == .additional ? name ?? section.title : section.title,
                        expirationDate: CredentialDates.dayString(expiration), status: status)
        }.sorted {
            if ($0.status == .expired) != ($1.status == .expired) { return $0.status == .expired }
            if $0.expirationDate != $1.expirationDate { return $0.expirationDate < $1.expirationDate }
            return $0.id.rawValue < $1.id.rawValue
        }
    }
}

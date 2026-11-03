import Foundation
import Combine

enum CredentialSection: String, CaseIterable, Identifiable {
    case commission, insurance, backgroundCheck, additional
    var id: String { rawValue }
    var title: String {
        switch self {
        case .commission: "Notary Commission"
        case .insurance: "E&O Insurance"
        case .backgroundCheck: "Background Check"
        case .additional: "Credential"
        }
    }
    var fields: [CredentialField] {
        switch self {
        case .commission: [
            .init("commissionNumber", "Commission number", \.commissionNumber),
            .init("commissionState", "Issuing state", \.commissionState),
            .init("commissionStartDate", "Start date", \.commissionStartDate, .date),
            .init("commissionExpirationDate", "Expiration date", \.commissionExpirationDate, .expiration)
        ]
        case .insurance: [
            .init("eoProvider", "Provider", \.eoProvider),
            .init("eoPolicyNumber", "Policy number", \.eoPolicyNumber),
            .init("eoCoverageAmount", "Coverage amount", \.eoCoverageAmount, .coverage),
            .init("eoStartDate", "Start date", \.eoStartDate, .date),
            .init("eoExpirationDate", "Expiration date", \.eoExpirationDate, .expiration)
        ]
        case .backgroundCheck: [
            .init("backgroundCheckProvider", "Provider", \.backgroundCheckProvider),
            .init("backgroundCheckCompletedDate", "Completion date", \.backgroundCheckCompletedDate, .date),
            .init("backgroundCheckExpirationDate", "Expiration date", \.backgroundCheckExpirationDate, .expiration)
        ]
        case .additional: [
            .init("certificationName", "Credential name", \.certificationName),
            .init("certificationExpirationDate", "Expiration date", \.certificationExpirationDate, .expiration)
        ]
        }
    }
    var expirationKey: WritableKeyPath<Credentials, String?> { fields.last!.key }
    func isAdded(in credentials: Credentials) -> Bool {
        fields.contains { !(credentials[keyPath: $0.key]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) }
    }
    static let summarySections: [Self] = [.commission, .insurance, .backgroundCheck]
}

struct CredentialField: Identifiable {
    enum Kind { case text, date, expiration, coverage }
    let id: String
    let title: String
    let key: WritableKeyPath<Credentials, String?>
    let kind: Kind
    init(_ id: String, _ title: String, _ key: WritableKeyPath<Credentials, String?>, _ kind: Kind = .text) {
        self.id = id; self.title = title; self.key = key; self.kind = kind
    }
    var isDate: Bool { kind == .date || kind == .expiration }
}

enum CredentialExpiration: Equatable {
    case missing, invalid, expired, expiringSoon(days: Int), current
    var badgeTitle: String? {
        switch self {
        case .expired: "Expired"
        case .expiringSoon: "Expiring soon"
        default: nil
        }
    }
    var accessibleDescription: String {
        switch self {
        case .missing: "Expiration date not provided"
        case .invalid: "Invalid expiration date"
        case .expired: "Expired"
        case .expiringSoon(let days): days == 0 ? "Expiring soon, expires today" : "Expiring soon, expires in \(days) days"
        case .current: "Expiration is more than one month away"
        }
    }
}

enum CredentialDates {
    static func localCalendar(_ calendar: Calendar) -> Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = calendar.timeZone
        return result
    }
    // Date-only backend timestamps keep their written day, without UTC conversion.
    static func dayString(_ value: String?) -> String {
        let value = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.contains("T") ? String(value.prefix(10)) : value
    }
    static func date(_ value: String?, calendar: Calendar = .current) -> Date? {
        let value = dayString(value)
        guard value.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"#, options: .regularExpression) != nil else { return nil }
        let parts = value.split(separator: "-").compactMap { Int($0) }
        let calendar = localCalendar(calendar)
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)
        guard let date = calendar.date(from: components) else { return nil }
        let actual = calendar.dateComponents([.year, .month, .day], from: date)
        guard actual.year == parts[0], actual.month == parts[1], actual.day == parts[2] else { return nil }
        return date
    }
    static func status(_ value: String?, today: Date = Date(), calendar: Calendar = .current) -> CredentialExpiration {
        guard !dayString(value).isEmpty else { return .missing }
        guard let date = date(value, calendar: calendar) else { return .invalid }
        let calendar = localCalendar(calendar)
        let start = calendar.startOfDay(for: today)
        let expiration = calendar.startOfDay(for: date)
        if expiration < start { return .expired }
        if let boundary = calendar.date(byAdding: .month, value: 1, to: start), expiration <= boundary {
            return .expiringSoon(days: calendar.dateComponents([.day], from: start, to: expiration).day ?? 0)
        }
        return .current
    }
}

extension Credentials {
    var normalizedForEditing: Credentials {
        var result = self
        for field in CredentialSection.allCases.flatMap(\.fields) {
            let value = self[keyPath: field.key]?.trimmingCharacters(in: .whitespacesAndNewlines)
            result[keyPath: field.key] = (field.isDate ? CredentialDates.dayString(value) : value ?? "").nilIfEmpty
        }
        result.commissionState = result.commissionState?.uppercased()
        return result
    }
}

@MainActor
final class CredentialsEditorModel: ObservableObject {
    @Published private(set) var draft: Credentials
    @Published private(set) var saved: Credentials?
    @Published var isExpanded = false
    @Published var isAdditionalExpanded = false
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var error = ""
    @Published private(set) var success = ""
    private let fetch: () async throws -> Credentials
    private let persist: (Credentials) async throws -> Credentials

    // No actor-bound cleanup is needed. Avoid isolated-deinit runtime crashes on
    // iOS 26.1 when SwiftUI releases the editor outside a Swift task.
    // https://github.com/swiftlang/swift/issues/88036
    nonisolated deinit {}

    init(saved: Credentials? = nil,
         fetch: @escaping () async throws -> Credentials = { try await APIService.shared.fetchCredentials() },
         persist: @escaping (Credentials) async throws -> Credentials = { try await APIService.shared.updateCredentials($0) }) {
        self.saved = saved?.normalizedForEditing
        self.draft = saved?.normalizedForEditing ?? Credentials()
        self.fetch = fetch; self.persist = persist
    }
    var isBusy: Bool { isLoading || isSaving }
    var canEdit: Bool { saved != nil && !isBusy }
    var hasChanges: Bool { saved.map { draft.normalizedForEditing != $0 } ?? false }
    var canSave: Bool { hasChanges && !isBusy }
    var addedSections: [CredentialSection] {
        guard let saved else { return [] }
        return CredentialSection.summarySections.filter { $0.isAdded(in: saved) }
    }
    func edit(_ field: CredentialField, value: String) {
        guard canEdit else { return }
        draft[keyPath: field.key] = (field.id == "commissionState" ? value.uppercased() : value).nilIfEmpty
        error = ""; success = ""
    }
    func load() async {
        guard saved == nil, !isBusy else { return }
        isLoading = true; error = ""
        defer { isLoading = false }
        do {
            let result = try await fetch().normalizedForEditing
            saved = result; draft = result
        } catch { self.error = error.localizedDescription }
    }
    func save() async {
        guard canSave else { return }
        error = ""; success = ""
        let submitted = draft.normalizedForEditing
        for section in CredentialSection.allCases {
            for field in section.fields where field.isDate {
                if let value = submitted[keyPath: field.key], CredentialDates.date(value) == nil {
                    error = "Enter a valid \(section.title.lowercased()) \(field.title.lowercased()) as YYYY-MM-DD."
                    return
                }
            }
            if section != .additional, section.isAdded(in: submitted), submitted[keyPath: section.expirationKey] == nil {
                error = "Enter the \(section.title.lowercased()) expiration date."
                return
            }
        }
        if let completed = CredentialDates.date(submitted.backgroundCheckCompletedDate),
           let expiration = CredentialDates.date(submitted.backgroundCheckExpirationDate), expiration < completed {
            error = "Background check expiration must be on or after completion."
            return
        }
        do { _ = try submitted.requestBody() }
        catch { self.error = error.localizedDescription; return }
        isSaving = true
        defer { isSaving = false }
        do {
            let result = try await persist(submitted).normalizedForEditing
            saved = result; draft = result
            success = "Your credentials have been saved."
        } catch { self.error = error.localizedDescription }
    }
}

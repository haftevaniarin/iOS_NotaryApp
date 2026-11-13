import Foundation

enum LedgerReportKind: String, CaseIterable, Identifiable {
    case overview, income, profitLoss = "profit-loss", outstanding, mileage, expenses, clients
    var id: String { rawValue }
    var endpoint: String { "/api/reports/" + (self == .outstanding ? "outstanding-payments" : rawValue) }
    var title: String {
        switch self {
        case .overview: "Overview"
        case .income: "Income"
        case .profitLoss: "Profit & Loss"
        case .outstanding: "Outstanding Payments"
        case .mileage: "Mileage"
        case .expenses: "Expenses"
        case .clients: "Clients"
        }
    }
    var showsPaymentStatus: Bool { self == .income || self == .outstanding }
    var showsOrderStatus: Bool { self == .income || self == .clients }
}

enum ReportPeriod: String, CaseIterable, Identifiable {
    case thisMonth = "this-month", lastMonth = "last-month", yearToDate = "year-to-date", lastYear = "last-year", custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .thisMonth: "This Month"
        case .lastMonth: "Last Month"
        case .yearToDate: "Year to Date"
        case .lastYear: "Last Year"
        case .custom: "Custom"
        }
    }
}

struct ReportFilters: Equatable, Hashable {
    var period: ReportPeriod = .thisMonth
    var startDate = Date()
    var endDate = Date()
    var clientID = ""
    var paymentStatus = "All"
    var orderStatus = "All"
    static var localCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }

    // Like the web, presets are local calendar days sent explicitly to the server.
    // The backend owns inclusive end dates, aggregation, aging, and status rules.
    func dateRange(now: Date = Date(), calendar: Calendar = Self.localCalendar) -> (start: String, end: String)? {
        let start: Date
        let end: Date
        switch period {
        case .custom:
            start = startDate; end = endDate
        case .thisMonth, .lastMonth:
            let anchor = period == .lastMonth ? calendar.date(byAdding: .month, value: -1, to: now) : now
            guard let anchor, let interval = calendar.dateInterval(of: .month, for: anchor),
                  let lastDay = calendar.date(byAdding: .day, value: -1, to: interval.end) else { return nil }
            start = interval.start; end = lastDay
        case .yearToDate, .lastYear:
            guard let interval = calendar.dateInterval(of: .year, for: now) else { return nil }
            if period == .yearToDate { start = interval.start; end = now }
            else {
                guard let previous = calendar.date(byAdding: .year, value: -1, to: interval.start),
                      let lastDay = calendar.date(byAdding: .day, value: -1, to: interval.start) else { return nil }
                start = previous; end = lastDay
            }
        }
        func key(_ date: Date) -> String {
            let day = calendar.dateComponents([.year, .month, .day], from: date)
            return String(format: "%04d-%02d-%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0)
        }
        let range = (start: key(start), end: key(end))
        return range.start <= range.end ? range : nil
    }

    func queryItems(now: Date = Date(), calendar: Calendar = Self.localCalendar) throws -> [URLQueryItem] {
        guard let range = dateRange(now: now, calendar: calendar) else { throw ReportError.invalidDateRange }
        var items = [URLQueryItem(name: "period", value: period.rawValue),
                     URLQueryItem(name: "startDate", value: range.start), URLQueryItem(name: "endDate", value: range.end)]
        for (key, value) in [("clientId", clientID), ("paymentStatus", paymentStatus), ("orderStatus", orderStatus)] {
            let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty && value != "All" { items.append(URLQueryItem(name: key, value: value)) }
        }
        return items
    }
}

enum ReportError: LocalizedError {
    case invalidDateRange, invalidResponse
    var errorDescription: String? {
        switch self {
        case .invalidDateRange: "Start date must be on or before end date."
        case .invalidResponse: "No recognizable report data was returned. Please try again."
        }
    }
}

// A report retains the backend's complete record shape and Decimal precision.
// Missing/null values remain absent rather than becoming invented zero totals.
indirect enum ReportValue: Decodable, Equatable {
    case object([String: ReportValue]), array([ReportValue]), number(Decimal), text(String), bool(Bool), null
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let object = try? container.decode([String: ReportValue].self) { self = .object(object) }
        else if let array = try? container.decode([ReportValue].self) { self = .array(array) }
        else if let text = try? container.decode(String.self) { self = .text(text) }
        else if let bool = try? container.decode(Bool.self) { self = .bool(bool) }
        else { self = .number(try container.decode(Decimal.self)) }
    }
    subscript(_ path: String) -> ReportValue {
        path.split(separator: ".").reduce(self) { value, key in
            if case .object(let object) = value { return object[String(key)] ?? .null }
            return .null
        }
    }
    var decimal: Decimal? {
        switch self {
        case .number(let value): value
        case .text(let value): Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))
        default: nil
        }
    }
    var text: String? { if case .text(let value) = self { return value.isEmpty ? nil : value }; return nil }
    var rows: [ReportValue] { if case .array(let values) = self { return values }; return [] }
}

struct LedgerReport: Equatable {
    let root: ReportValue
    init(data: Data) throws {
        var value = try JSONDecoder().decode(ReportValue.self, from: data)
        for _ in 0..<5 {
            if value["success"] == .bool(false) { throw ReportError.invalidResponse }
            if case .object = value["data"] { value = value["data"] }
            else if case .object = value["report"] { value = value["report"] }
            else { break }
        }
        guard case .object = value,
              ["totals", "metrics", "clients", "items", "trend", "byMonth"].contains(where: { value[$0] != .null }) else {
            throw ReportError.invalidResponse
        }
        root = value
    }
    var totals: ReportValue { root["totals"] != .null ? root["totals"] : root["metrics"] }
}

struct ReportClientOption: Identifiable {
    let id: String
    let name: String
    static func from(_ orders: [SigningOrder]) -> [ReportClientOption] {
        var names: [String: String] = [:]
        for order in orders {
            guard let id = order.customerId?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else { continue }
            let name = order.customerName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, id.lowercased() != name.lowercased() else { continue }
            if names[id] == nil { names[id] = name }
        }
        return names.map { ReportClientOption(id: $0.key, name: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

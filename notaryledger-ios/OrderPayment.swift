import Foundation

enum SigningPaymentMode: String, CaseIterable, Identifiable {
    case automatic = "Automatic"
    case paid = "Paid"
    case cancelled = "Cancelled"

    var id: String { rawValue }
    var requestStatus: SigningStatus {
        switch self {
        case .automatic: .scheduled
        case .paid: .paid
        case .cancelled: .cancelled
        }
    }
}

struct SigningPaymentDraft: Equatable {
    var mode: SigningPaymentMode = .automatic
    var paidDate: String?
    var isPaid: Bool { mode == .paid }

    init(order: SigningOrder? = nil) {
        guard let order else { return }
        mode = order.normalizedStatus == .cancelled ? .cancelled : order.normalizedStatus == .paid ? .paid : .automatic
        paidDate = isPaid ? order.paidDate.flatMap { OrderCalendarDay($0)?.key } : nil
    }

    mutating func select(_ mode: SigningPaymentMode, today: String = OrderCalendarDay(date: Date()).key) {
        self.mode = mode
        paidDate = mode == .paid ? paidDate ?? today : nil
    }

    mutating func setPaid(_ paid: Bool) {
        guard mode != .cancelled else { return }
        select(paid ? .paid : .automatic)
    }

    mutating func setHasPaidDate(_ enabled: Bool, today: String = OrderCalendarDay(date: Date()).key) {
        guard isPaid else { return }
        paidDate = enabled ? paidDate ?? today : nil
    }
}

enum OrderDueDateUpdate: Equatable {
    case unchanged
    case set(String)
    case clear

    static func fromForm(_ value: String, original: String?) -> Self {
        if value == (original ?? "") { return .unchanged }
        return value.isEmpty ? .clear : .set(value)
    }
}

// Only mocks and legacy responses without paymentStatus calculate a status here.
// A real API response's calculated paymentStatus remains authoritative.
nonisolated enum OrderPaymentRules {
    static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    static func utcDay(_ date: Date) -> String {
        OrderCalendarDay(date: date, timeZone: utcCalendar.timeZone).key
    }

    static func signingDay(_ value: String) -> String? {
        if value.count == 10 { return OrderCalendarDay(value)?.key }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value) else { return nil }
        return utcDay(date)
    }

    static func status(date: String, dueDate: String?, paid: Bool, cancelled: Bool, now: Date = Date()) -> SigningStatus {
        if cancelled { return .cancelled }
        if paid { return .paid }
        let today = utcDay(now)
        if let dueDate, let day = OrderCalendarDay(dueDate), day.key < today { return .overdue }
        if let day = signingDay(date), day < today { return .pending }
        return .scheduled
    }

    static func nextRefresh(after now: Date) -> Date {
        utcCalendar.date(byAdding: .day, value: 1, to: utcCalendar.startOfDay(for: now))!
    }
}

import Foundation
import Observation

nonisolated struct OrderScheduleInput: Equatable, Sendable {
    var date: String
    var time: String
    var excludedOrderID: String?
    var timeZoneID: String = TimeZone.current.identifier
    var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? .current }
}

struct OrderScheduleConflict: Equatable {
    let order: SigningOrder
    let scheduledAt: Date
    let distance: TimeInterval
    let timeZone: TimeZone
    var appointmentLabel: String {
        let day = DateFormatter(); day.timeZone = timeZone; day.setLocalizedDateFormatFromTemplate("MMMMd")
        let clock = DateFormatter(); clock.timeZone = timeZone; clock.timeStyle = .short
        return "\(day.string(from: scheduledAt)) at \(clock.string(from: scheduledAt)) \(timeZone.abbreviation(for: scheduledAt) ?? timeZone.identifier)"
    }
    var message: String {
        "This appointment is within 2 hours of another signing, scheduled for \(appointmentLabel). Review the schedule; you can still save this order."
    }
}

enum OrderScheduleRules {
    // Web App.jsx getOrderScheduleOverlap: inclusive 120-minute start-time window,
    // no status exclusions or duration field, nearest match, warning only.
    static let warningWindow: TimeInterval = 120 * 60
    static func nearest(_ input: OrderScheduleInput, orders: [SigningOrder]) -> OrderScheduleConflict? {
        guard let draft = timestamp(date: input.date, time: input.time, timeZone: input.timeZone) else { return nil }
        var nearest: OrderScheduleConflict?
        for order in orders where order.id != input.excludedOrderID {
            guard let start = timestamp(for: order, timeZone: input.timeZone) else { continue }
            let distance = abs(start.timeIntervalSince(draft))
            if distance <= warningWindow && (nearest == nil || distance < nearest!.distance) {
                nearest = OrderScheduleConflict(order: order, scheduledAt: start, distance: distance, timeZone: input.timeZone)
            }
        }
        return nearest
    }
    static func timestamp(for order: SigningOrder, timeZone: TimeZone = .current) -> Date? {
        let instant = isoDate(order.date)
        let day = instant.map { OrderCalendarDay(date: $0, timeZone: timeZone) } ?? OrderCalendarDay(order.date)
        guard let day else { return nil }
        let time: String
        if order.hasExplicitTime { time = order.time ?? "" }
        else if let instant {
            let parts = OrderCalendarDay.localCalendar(timeZone).dateComponents([.hour, .minute], from: instant)
            // normalizeOrderForUi treats an embedded local midnight as "No time".
            guard parts.hour != 0 || parts.minute != 0 else { return nil }
            time = String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        } else { return nil }
        return timestamp(date: day.key, time: time, timeZone: timeZone)
    }
    static func timestamp(date: String, time: String, timeZone: TimeZone = .current) -> Date? {
        guard time.range(of: #"^([01][0-9]|2[0-3]):[0-5][0-9]$"#, options: .regularExpression) != nil,
              let day = OrderCalendarDay(date) else { return nil }
        let clock = time.split(separator: ":").compactMap { Int($0) }
        return OrderCalendarDay.localCalendar(timeZone).date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: clock[0], minute: clock[1]))
    }
    private static func isoDate(_ value: String) -> Date? {
        guard value.contains("T") else { return nil }
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

nonisolated struct OrderScheduleFailure: Equatable, Sendable {
    let message: String
    let orderID: String?
}

@MainActor @Observable
final class OrderSchedulingFeedback {
    nonisolated deinit {}
    private(set) var input = OrderScheduleInput(date: "", time: "")
    private(set) var orders: [SigningOrder] = []
    private(set) var serverFailure: OrderScheduleFailure?
    private(set) var refreshError: String?
    private(set) var isRefreshing = false
    private var ownerID: String?
    private var prepared = false
    private var revision = UUID()
    @ObservationIgnored private let fetch: @MainActor () async throws -> [SigningOrder]

    init(fetch: @escaping @MainActor () async throws -> [SigningOrder] = { try await APIService.shared.fetchOrders() }) { self.fetch = fetch }
    var conflict: OrderScheduleConflict? { OrderScheduleRules.nearest(input, orders: orders) }
    var conflictingOrder: SigningOrder? {
        if let serverFailure { return orders.first { $0.id == serverFailure.orderID } }
        return conflict?.order
    }
    func prepare(ownerID: String?, input: OrderScheduleInput, orders: [SigningOrder]) {
        if !prepared || self.ownerID != ownerID {
            revision = UUID(); self.ownerID = ownerID; serverFailure = nil; refreshError = nil; isRefreshing = false
            self.orders = orders; prepared = true
        }
        update(input)
    }
    func update(_ input: OrderScheduleInput) {
        if self.input != input { serverFailure = nil; refreshError = nil }
        self.input = input
    }
    func updateOrders(_ orders: [SigningOrder]) { self.orders = orders }
    @discardableResult func refresh() async throws -> [SigningOrder] {
        let owner = ownerID, request = UUID(); revision = request; isRefreshing = true; refreshError = nil
        defer { if revision == request { isRefreshing = false } }
        do {
            let orders = try await fetch()
            try Task.checkCancellation()
            guard self.ownerID == owner, revision == request else { throw CancellationError() }
            self.orders = orders // conflict is computed from the latest appointment, never the request's old date/time.
            return orders
        } catch {
            if self.ownerID == owner, revision == request, !RequestCancellation.isCancellation(error) {
                refreshError = "Could not check the latest schedule. Try again before saving."
            }
            throw error
        }
    }
    func report(_ failure: OrderScheduleFailure, for input: OrderScheduleInput) {
        guard self.input == input else { return }
        serverFailure = failure
    }
}

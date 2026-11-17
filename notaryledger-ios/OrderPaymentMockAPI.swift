#if DEBUG
import Foundation

nonisolated enum OrderPaymentMockError: Error {
    case invalidDueDate
}

// A stateful backend stand-in: omission preserves dueDate, null clears it, and
// every response recalculates status using the same UTC boundaries as the API.
nonisolated final class OrderPaymentMockStore: @unchecked Sendable {
    private let lock = NSLock()
    private var orders: [[String: Any]]?

    func reset() { lock.withLock { orders = nil } }

    func list(seed: [[String: Any]], now: Date = Date()) -> [[String: Any]] {
        lock.withLock {
            if orders == nil { orders = seed }
            return (orders ?? []).map { response($0, now: now) }
        }
    }

    func save(_ payload: [String: Any], id: String, now: Date = Date()) throws -> [String: Any] {
        if let value = payload["dueDate"], !(value is NSNull) {
            guard let day = value as? String, day.count == 10, OrderCalendarDay(day)?.key == day else {
                throw OrderPaymentMockError.invalidDueDate
            }
        }
        return lock.withLock {
            var rows = orders ?? []
            let index = rows.firstIndex { $0["id"] as? String == id }
            var saved = index.map { rows[$0] } ?? [:]
            saved.merge(payload) { _, new in new }
            saved["id"] = id
            if (saved["paymentStatus"] as? String)?.lowercased() == "cancelled" {
                saved["paid"] = false
                saved["paidDate"] = NSNull()
            } else if saved["paid"] as? Bool != true {
                saved["paidDate"] = NSNull()
            }
            if let index { rows[index] = saved } else { rows.append(saved) }
            orders = rows
            return response(saved, now: now)
        }
    }

    func remove(id: String) {
        lock.withLock { orders?.removeAll { $0["id"] as? String == id } }
    }

    private func response(_ order: [String: Any], now: Date) -> [String: Any] {
        var result = order
        let raw = (order["paymentStatus"] ?? order["status"]) as? String
        let status = OrderPaymentRules.status(
            date: order["date"] as? String ?? "",
            dueDate: order["dueDate"] as? String, paid: order["paid"] as? Bool == true,
            cancelled: ["cancelled", "canceled"].contains(raw?.lowercased() ?? ""), now: now)
        result["paymentStatus"] = status.rawValue
        result["dueDate"] = order["dueDate"] ?? NSNull()
        if status == .cancelled {
            result["paid"] = false
            result["paidDate"] = NSNull()
        }
        return result
    }
}
#endif

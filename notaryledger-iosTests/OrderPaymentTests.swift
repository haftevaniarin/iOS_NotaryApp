import Foundation
import Testing

@testable import notaryledger_ios

@MainActor struct OrderPaymentTests {
    private func instant(_ value: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: value))
    }

    private func payload(mode: SigningPaymentMode = .automatic, paidDate: String? = nil) -> SigningOrderPayload {
        SigningOrderPayload(
            customerName: "Title", payerName: "Payer", signerName: "Signer", signingType: "Refinance",
            date: "2026-11-16", time: "14:30", fee: 150, notarialActFee: 10, paid: mode == .paid,
            paidDate: paidDate, invoiceNumber: "DUE-1", notes: "Keep these notes", mileage: 12, travelFee: 5,
            status: mode.requestStatus)
    }

    private func json(_ payload: SigningOrderPayload) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any])
    }

    @Test func dueTodayIsPayableUntilTheNextUTCDayAndNoDueDateNeverBecomesOverdue() throws {
        let before = try instant("2026-11-16T23:59:59Z")
        let after = try instant("2026-11-17T00:00:00Z")
        #expect(OrderPaymentRules.status(date: "2026-11-15", dueDate: "2026-11-16", paid: false, cancelled: false, now: before) == .pending)
        #expect(OrderPaymentRules.status(date: "2026-11-15", dueDate: "2026-11-16", paid: false, cancelled: false, now: after) == .overdue)
        #expect(OrderPaymentRules.status(date: "2000-01-01", dueDate: nil, paid: false, cancelled: false, now: after) == .pending)
        #expect(OrderPaymentRules.status(date: "2026-11-17", dueDate: nil, paid: false, cancelled: false, now: after) == .scheduled)
        #expect(
            OrderPaymentRules.status(date: "2026-11-16T23:30:00-08:00", dueDate: nil, paid: false, cancelled: false, now: after)
                == .scheduled)
        #expect(OrderPaymentRules.status(date: "2026-11-16T23:30:00Z", dueDate: nil, paid: false, cancelled: false, now: after) == .pending)
        #expect(OrderPaymentRules.status(date: "2099-01-01", dueDate: "2026-11-16", paid: false, cancelled: false, now: after) == .overdue)
    }

    @Test func paidAndCancelledOverrideDates() throws {
        let now = try instant("2026-11-17T00:00:00Z")
        #expect(OrderPaymentRules.status(date: "2000-01-01", dueDate: "2000-02-01", paid: true, cancelled: false, now: now) == .paid)
        #expect(OrderPaymentRules.status(date: "2000-01-01", dueDate: "2000-02-01", paid: true, cancelled: true, now: now) == .cancelled)
    }

    @Test func dueDatePayloadDistinguishesPreserveSetAndClearAndKeepsRequiredFields() throws {
        var draft = payload()
        #expect(try json(draft)["dueDate"] == nil)
        draft.dueDate = .fromForm("2026-12-01", original: nil)
        let created = try json(draft)
        #expect(created["dueDate"] as? String == "2026-12-01")
        #expect(created["customerName"] as? String == "Title")
        #expect(created["signerName"] as? String == "Signer")
        #expect(created["fee"] as? Double == 150)
        #expect(created["invoiceNumber"] as? String == "DUE-1")
        #expect(created["notes"] as? String == "Keep these notes")
        draft.dueDate = .fromForm("2026-12-01", original: "2026-12-01")
        #expect(try json(draft)["dueDate"] == nil)
        draft.dueDate = .fromForm("", original: "2026-12-01")
        #expect(try json(draft)["dueDate"] is NSNull)
        draft.dueDate = .fromForm("2026-12-15", original: "2026-12-01")
        #expect(try json(draft)["dueDate"] as? String == "2026-12-15")
    }

    @Test func datePickerCalendarDatesRoundTripAcrossTimeZones() throws {
        let day = try #require(OrderCalendarDay("2026-03-08"))
        for zone in ["America/Los_Angeles", "Asia/Tokyo", "Pacific/Kiritimati", "Pacific/Pago_Pago"] {
            let timeZone = try #require(TimeZone(identifier: zone))
            let selected = day.date(timeZone: timeZone)
            let saved = OrderCalendarDay(date: selected, timeZone: timeZone).key
            var draft = payload()
            draft.dueDate = .set(saved)
            #expect(try json(draft)["dueDate"] as? String == "2026-03-08")
        }
    }

    @Test func controlsPreserveOptionalPaidDateAndAutomaticNeverAppearsInRequests() throws {
        let order = SigningOrder(
            id: "paid", customerName: "Title", signerName: "Signer", date: "2026-11-16",
            fee: 150, paid: true, status: .paid, dueDate: "2026-12-01")
        var draft = SigningPaymentDraft(order: order)
        #expect(draft.mode == .paid && draft.paidDate == nil)
        draft.setHasPaidDate(true, today: "2026-11-16")
        #expect(draft.paidDate == "2026-11-16")
        draft.setHasPaidDate(false)
        #expect(draft.isPaid && draft.paidDate == nil)
        draft.select(.cancelled)
        draft.setPaid(true)
        #expect(draft.mode == .cancelled && draft.paidDate == nil)
        draft.select(.automatic)
        let automatic = try json(payload(mode: draft.mode))
        #expect(automatic["paid"] as? Bool == false)
        #expect(automatic["paymentStatus"] as? String == "Scheduled")
        #expect(automatic["paidDate"] is NSNull)
        let paid = try json(payload(mode: .paid))
        #expect(paid["paid"] as? Bool == true && paid["paidDate"] is NSNull)
        let cancelled = try json(payload(mode: .cancelled, paidDate: "2026-11-16"))
        #expect(cancelled["paid"] as? Bool == false && cancelled["paidDate"] is NSNull)
    }

    @Test func serverPaymentStatusControlsBadgesFiltersAndTotals() throws {
        let body =
            #"[{"id":"paid","customerName":"Title","date":"2026-11-16","fee":150,"paid":false,"paymentStatus":"Paid","status":"Pending","dueDate":"2026-12-01"},{"id":"pending","customerName":"Title","date":"2026-11-16","fee":100,"paid":false,"paymentStatus":"Pending"},{"id":"overdue","customerName":"Title","date":"2026-11-16","fee":200,"paid":false,"paymentStatus":"Overdue"},{"id":"cancelled","customerName":"Title","date":"2026-11-16","fee":9000,"paid":true,"paymentStatus":"Cancelled"}]"#
        let orders = try JSONDecoder().decode([SigningOrder].self, from: Data(body.utf8))
        #expect(orders.map(\.normalizedStatus) == [.paid, .pending, .overdue, .cancelled])
        #expect(orders[0].dueDate == "2026-12-01")
        #expect(orders.filter(\.isUnpaidCandidate).map(\.id) == ["pending", "overdue"])
        #expect(CustomerSummaries.build(from: orders).first?.revenue == 150)
        let stats = LedgerDashboardSnapshot.make(orders: orders, expenses: [], now: try instant("2026-11-16T12:00:00Z"))
        #expect(stats.monthStats.netIncome == 150)
        let scheduled = try JSONDecoder().decode(
            SigningOrder.self,
            from: Data(#"{"id":"scheduled","date":"2000-01-01","dueDate":"2000-02-01","paymentStatus":"Scheduled"}"#.utf8))
        #expect(scheduled.normalizedStatus == .scheduled)
    }

    @Test func mocksRecalculateAfterCreationExtensionClearingAndRescheduling() throws {
        let store = OrderPaymentMockStore()
        let now = try instant("2026-11-17T00:00:00Z")
        var create = try json(payload())
        create["date"] = "2026-11-15"
        create["dueDate"] = "2026-11-16"
        let overdue = try store.save(create, id: "order", now: now)
        #expect(overdue["paymentStatus"] as? String == "Overdue")
        let preserved = try store.save(["notes": "Edited"], id: "order", now: now)
        #expect(preserved["dueDate"] as? String == "2026-11-16")
        let extended = try store.save(["dueDate": "2026-12-01"], id: "order", now: now)
        #expect(extended["paymentStatus"] as? String == "Pending")
        let cleared = try store.save(["dueDate": NSNull()], id: "order", now: now)
        #expect(cleared["dueDate"] is NSNull && cleared["paymentStatus"] as? String == "Pending")
        let rescheduled = try store.save(["date": "2026-11-18"], id: "order", now: now)
        #expect(rescheduled["paymentStatus"] as? String == "Scheduled")
        #expect(rescheduled["invoiceNumber"] as? String == "DUE-1")
        #expect(store.list(seed: [], now: now).first?["paymentStatus"] as? String == "Scheduled")
        let paid = try store.save(["paid": true, "paymentStatus": "Paid", "dueDate": "2000-01-01"], id: "order", now: now)
        #expect(paid["paymentStatus"] as? String == "Paid")
        let cancelled = try store.save(["paymentStatus": "Cancelled"], id: "order", now: now)
        #expect(cancelled["paymentStatus"] as? String == "Cancelled" && cancelled["paid"] as? Bool == false)
        let automatic = try store.save(["paid": false, "paymentStatus": "Scheduled", "dueDate": NSNull()], id: "order", now: now)
        #expect(automatic["paymentStatus"] as? String == "Scheduled")
    }

    @Test func mocksRejectInvalidDueDatesAndRefreshAtUTCMidnight() throws {
        let store = OrderPaymentMockStore()
        for invalid in ["", "2026-02-30", "11/16/2026", "2026-11-16T00:00:00Z"] {
            #expect(throws: OrderPaymentMockError.self) { try store.save(["dueDate": invalid], id: "bad") }
        }
        let now = try instant("2026-11-16T23:59:59Z")
        let midnight = OrderPaymentRules.nextRefresh(after: now)
        #expect(midnight == (try instant("2026-11-17T00:00:00Z")))
        #expect(OrderPaymentRules.nextRefresh(after: midnight) == (try instant("2026-11-18T00:00:00Z")))
        _ = try store.save(["date": "2026-11-15", "dueDate": "2026-11-16", "paid": false], id: "due", now: now)
        #expect(store.list(seed: [], now: now).first?["paymentStatus"] as? String == "Pending")
        #expect(store.list(seed: [], now: midnight).first?["paymentStatus"] as? String == "Overdue")
    }
}

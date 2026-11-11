import Foundation
import Testing
@testable import notaryledger_ios

private final class OrderRuleFixtureBundle {}
private struct WebOrderRuleFixtures: Decodable {
    struct CalendarCase: Decodable {
        struct Skipped: Decodable { let date: String; let reason: String }
        let date: String; let deadlineDate: String; let skippedDays: [Skipped]
    }
    struct ScheduleCase: Decodable {
        struct Draft: Decodable { let date: String; let time: String }
        let name: String; let timeZone: String; let draft: Draft
        let orders: [SigningOrder]; let excludedOrderID: String?; let expectedOrderID: String?
    }
    let rescission: [CalendarCase]
    let scheduling: [ScheduleCase]
}

@MainActor
struct OrderAppointmentFeedbackTests {
    private func fixtures() throws -> WebOrderRuleFixtures {
        let url = try #require(Bundle(for: OrderRuleFixtureBundle.self).url(forResource: "order-rule-web-parity", withExtension: "json"))
        return try JSONDecoder().decode(WebOrderRuleFixtures.self, from: Data(contentsOf: url))
    }
    private func order(_ id: String = "1234", date: String = "2026-11-12", time: String = "14:00") -> SigningOrder {
        SigningOrder(id: id, customerName: "Sample title", signerName: "Sample signer", date: date, time: time, fee: 100, paid: false)
    }
    @Test func schedulingMatchesActualWebRulesAcrossTimeZonesAndDST() throws {
        for test in try fixtures().scheduling {
            let input = OrderScheduleInput(date: test.draft.date, time: test.draft.time, excludedOrderID: test.excludedOrderID, timeZoneID: test.timeZone)
            #expect(OrderScheduleRules.nearest(input, orders: test.orders)?.order.id == test.expectedOrderID, "\(test.timeZone): \(test.name)")
        }
    }
    @Test func rescissionMatchesWebCalendarIncludingObservedAndMovingHolidays() throws {
        for test in try fixtures().rescission {
            let result = try #require(RescissionRules.calculate(signingDate: test.date))
            #expect(result.date.key == test.deadlineDate, "Signing date \(test.date)")
            #expect(result.skippedDays.map(\.date.key) == test.skippedDays.map(\.date))
            #expect(result.skippedDays.map(\.reason) == test.skippedDays.map(\.reason))
        }
    }
    @Test func rescissionExplainsMissingDataEligibilityAndInvalidCalendarDates() throws {
        #expect(OrderRescissionFeedback(signingType: "", signingDate: "2026-11-12") == .missingType)
        #expect(OrderRescissionFeedback(signingType: "Refinance", signingDate: "") == .missingDate)
        #expect(OrderRescissionFeedback(signingType: "HELOC", signingDate: "2026-02-29") == .invalidDate)
        for type in ["Loan Signing", "Seller Package", "General Notary", "Other"] {
            #expect(OrderRescissionFeedback(signingType: type, signingDate: "2026-11-12") == .notApplicable)
        }
        #expect(RescissionRules.calculate(signingDate: "2024-02-28")?.date.key == "2024-03-02")
        #expect(RescissionRules.calculate(signingDate: "2021-12-29")?.date.key == "2022-01-03")
        for invalid in ["", "2026-13-01", "2026-04-31", "11/12/2026", "tomorrow"] {
            #expect(RescissionRules.calculate(signingDate: invalid) == nil)
        }
        let day = try #require(OrderCalendarDay("2026-03-08"))
        for zone in ["America/Los_Angeles", "America/New_York", "Pacific/Kiritimati"] {
            let timeZone = try #require(TimeZone(identifier: zone))
            #expect(OrderCalendarDay(date: day.date(timeZone: timeZone), timeZone: timeZone).key == "2026-03-08")
        }
    }
    @Test func liveConflictResolvesAndStaleServerFeedbackIsDiscarded() {
        let model = OrderSchedulingFeedback(fetch: { [] })
        let input = OrderScheduleInput(date: "2026-11-12", time: "14:30")
        model.prepare(ownerID: "owner", input: input, orders: [order()])
        #expect(model.conflict?.order.id == "1234")
        #expect(model.conflict?.message.contains("within 2 hours") == true)
        #expect(model.conflict?.message.contains("can still save") == true)
        model.report(OrderScheduleFailure(message: "Server conflict", orderID: "1234"), for: input)
        #expect(model.serverFailure != nil && model.conflictingOrder?.id == "1234")
        model.update(OrderScheduleInput(date: "2026-11-12", time: "17:00"))
        #expect(model.conflict == nil && model.serverFailure == nil)
        model.report(OrderScheduleFailure(message: "Outdated response", orderID: "1234"), for: input)
        #expect(model.serverFailure == nil)
        model.update(OrderScheduleInput(date: "2026-11-13", time: "14:00"))
        #expect(model.conflict == nil)
    }
    @Test func delayedRefreshUsesLatestAppointmentAndCannotCrossAccounts() async throws {
        let signal = AsyncStream<Void>.makeStream()
        var pending: CheckedContinuation<[SigningOrder], Error>?
        let model = OrderSchedulingFeedback(fetch: {
            try await withCheckedThrowingContinuation { continuation in
                pending = continuation; signal.continuation.yield(())
            }
        })
        var iterator = signal.stream.makeAsyncIterator()
        model.prepare(ownerID: "first", input: OrderScheduleInput(date: "2026-11-12", time: "14:00"), orders: [])
        let request = Task { try await model.refresh() }
        await iterator.next()
        model.update(OrderScheduleInput(date: "2026-11-12", time: "18:00"))
        pending?.resume(returning: [order()])
        _ = try await request.value
        #expect(model.conflict == nil)
        model.prepare(ownerID: "first", input: model.input, orders: [])
        #expect(model.orders.map(\.id) == ["1234"], "Returning from order details must keep the refreshed schedule.")
        let second = Task { try await model.refresh() }
        await iterator.next()
        model.prepare(ownerID: "second", input: OrderScheduleInput(date: "2026-11-12", time: "14:00"), orders: [order("owned-by-second")])
        pending?.resume(returning: [order("owned-by-first")])
        do { _ = try await second.value; Issue.record("Old account response must be rejected") } catch is CancellationError {} catch { Issue.record("Unexpected error: \(error)") }
        #expect(model.conflict?.order.id == "owned-by-second")
    }
    @Test func refreshFailureCanRetryWithoutLosingTheAppointment() async throws {
        var failing = true
        let existing = order()
        let model = OrderSchedulingFeedback(fetch: { if failing { throw URLError(.notConnectedToInternet) }; return [existing] })
        let input = OrderScheduleInput(date: "2026-11-12", time: "14:00")
        model.prepare(ownerID: "owner", input: input, orders: [existing])
        do { try await model.refresh(); Issue.record("Expected offline error") } catch {}
        #expect(model.refreshError != nil && model.input == input)
        failing = false
        try await model.refresh()
        #expect(model.refreshError == nil && model.conflict?.order.id == existing.id)
    }
    @Test func serverScheduleErrorsMapInlineWithoutMisclassifyingOtherConflicts() throws {
        let data = Data(#"{"error":{"code":"SCHEDULE_CONFLICT","message":"This appointment overlaps another order.","conflictingOrderId":"1234"}}"#.utf8)
        let failure = try #require(OrderValidationFailure.fromResponse(data))
        #expect(failure.fieldErrors["schedule"] == "This appointment overlaps another order.")
        #expect(failure.scheduleConflict?.orderID == "1234")
        #expect(OrderValidationFailure.fromResponse(Data(#"{"error":{"code":"INVOICE_CONFLICT","message":"Invoice already exists."}}"#.utf8)) == nil)
    }
}

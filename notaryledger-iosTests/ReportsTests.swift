import Foundation
import Testing
@testable import notaryledger_ios

@MainActor @Suite(.serialized) struct ReportsTests {
    private func report(_ json: String = #"{"totals":{"grossRevenue":"123.45"},"trend":[]}"#) throws -> LedgerReport {
        try LedgerReport(data: Data(json.utf8))
    }
    @Test func datePresetsMatchWebCalendarDaysAcrossYearAndDSTBoundaries() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 1, day: 5, hour: 12)))
        var filters = ReportFilters()
        #expect(filters.dateRange(now: now, calendar: calendar)?.start == "2026-01-01")
        #expect(filters.dateRange(now: now, calendar: calendar)?.end == "2026-01-31")
        filters.period = .lastMonth
        #expect(filters.dateRange(now: now, calendar: calendar)?.start == "2025-12-01")
        #expect(filters.dateRange(now: now, calendar: calendar)?.end == "2025-12-31")
        filters.period = .yearToDate
        #expect(filters.dateRange(now: now, calendar: calendar)?.end == "2026-01-05")
        filters.period = .lastYear
        #expect(filters.dateRange(now: now, calendar: calendar)?.start == "2025-01-01")
        filters.period = .thisMonth
        let leap = try #require(calendar.date(from: DateComponents(year: 2024, month: 2, day: 15)))
        #expect(filters.dateRange(now: leap, calendar: calendar)?.end == "2024-02-29")
        let dst = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 9)))
        #expect(filters.dateRange(now: dst, calendar: calendar)?.end == "2026-03-31")
        filters.period = .custom; filters.startDate = now; filters.endDate = leap
        #expect(filters.dateRange(calendar: calendar) == nil)
        #expect(throws: ReportError.self) { try filters.queryItems(calendar: calendar) }
    }
    @Test func reportResponsesPreserveOutstandingItemsAndExactAmounts() throws {
        let result = try report(#"{"success":true,"data":{"report":{"totals":{"totalOutstanding":"900.25","mileageRate":null},"items":[{"orderId":"123","amountDue":"900.25"}]}}}"#)
        #expect(result.totals["totalOutstanding"].decimal == Decimal(string: "900.25"))
        #expect(result.root["items"].rows.first?["orderId"].text == "123")
        #expect(result.totals["mileageRate"].decimal == nil)
        #expect(ReportField("mileageRate", "Mileage Rate").formatted(in: result.totals) == nil)
        #expect(throws: (any Error).self) { try report(#"{"success":false,"data":{"totals":{}}}"#) }
        #expect(throws: (any Error).self) { try report("{}") }
        #expect(try report(#"{"totals":{},"clients":[]}"#).root["clients"].rows.isEmpty)
    }
    @Test func clientFiltersUseBackendIDsInsteadOfNames() throws {
        let orders = try JSONDecoder().decode([SigningOrder].self, from: Data(#"[{"id":"1","customerName":"Harbor Title","customerId":"customer-1"},{"id":"2","customerName":"Harbor Title","clientId":"customer-1"},{"id":"3","customerName":"Legacy name"}]"#.utf8))
        let options = ReportClientOption.from(orders)
        #expect(options.count == 1 && options.first?.id == "customer-1")
        var filters = ReportFilters(); filters.clientID = "customer-1"; filters.paymentStatus = "Paid"
        let query = try filters.queryItems()
        #expect(query.first { $0.name == "clientId" }?.value == "customer-1")
        #expect(!query.contains { $0.name == "client" || $0.name == "orderStatus" })
        #expect(AuthLink(url: try #require(URL(string: "notaryledger://reports")))?.destination == .reports)
        #expect(LedgerTab(section: .reports) == .money)
    }
    @Test func supersededReportsCannotReplaceNewFilters() async throws {
        let started = AsyncStream<Void>.makeStream()
        var pending: CheckedContinuation<LedgerReport, any Error>?
        let fresh = try report(#"{"totals":{"totalExpenses":25},"expenses":[]}"#)
        let oldReport = try report()
        let model = ReportsViewModel { kind, _ in
            if kind == .income {
                return try await withCheckedThrowingContinuation { pending = $0; started.continuation.yield(()) }
            }
            return fresh
        }
        let old = Task { await model.load(ReportRequest(kind: .income, filters: ReportFilters(), ownerID: "account")) }
        var iterator = started.stream.makeAsyncIterator(); await iterator.next()
        await model.load(ReportRequest(kind: .expenses, filters: ReportFilters(), ownerID: "account"))
        pending?.resume(returning: oldReport); await old.value
        #expect(model.report == fresh && !model.isLoading && model.errorMessage == nil)
    }
    @Test func reportErrorsHaveClearAccountAndUnavailableStates() async {
        let model = ReportsViewModel { _, _ in throw APIError.httpError(404, "Missing") }
        await model.load(ReportRequest(kind: .overview, filters: ReportFilters(), ownerID: "account"))
        #expect(model.report == nil && model.errorMessage == "This report is not available yet." && !model.isLoading)
        await model.load(ReportRequest(kind: .overview, filters: ReportFilters(), ownerID: nil))
        #expect(model.errorMessage == "Sign in to view reports.")
    }
}

extension ValidationAndAPITests {
    @Test func businessReportsUseAllWebEndpointsAndAuthenticatedFilters() async throws {
        let previousToken = SessionStorage.getAccessToken()
        SessionStorage.saveAccessToken("report-fixture-token")
        defer {
            MockURLProtocol.requestHandler = nil
            if let previousToken { SessionStorage.saveAccessToken(previousToken) } else { SessionStorage.clearTokens() }
        }
        let expected = ["overview", "income", "profit-loss", "outstanding-payments", "mileage", "expenses", "clients"]
        for (index, kind) in LedgerReportKind.allCases.enumerated() {
            MockURLProtocol.requestHandler = { request in
                if request.url?.path == "/api/config/maintenance" {
                    return MockURLProtocol.jsonResponse(for: request, body: #"{"enabled":false}"#)
                }
                #expect(request.url?.path == "/api/reports/" + expected[index])
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer report-fixture-token")
                #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
                let query = URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
                #expect(query.first { $0.name == "clientId" }?.value == "customer-123")
                #expect(query.first { $0.name == "paymentStatus" }?.value == "Paid")
                #expect(!query.contains { $0.name == "client" || $0.name == "orderStatus" })
                return MockURLProtocol.jsonResponse(for: request, body: #"{"success":true,"data":{"report":{"totals":{"totalOutstanding":"45.25"},"items":[{"orderId":"123"}]}}}"#)
            }
            var filters = ReportFilters(); filters.clientID = "customer-123"; filters.paymentStatus = "Paid"
            let api = APIService(baseURL: "https://reports.example.test", session: MockURLProtocol.session())
            let report = try await api.fetchBusinessReport(kind: kind, filters: filters)
            #expect(report.root["items"].rows.count == 1 && report.totals["totalOutstanding"].decimal == Decimal(string: "45.25"))
        }
    }
}

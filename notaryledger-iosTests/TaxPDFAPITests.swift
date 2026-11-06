import Foundation
import Testing
@testable import notaryledger_ios

extension ValidationAndAPITests {
    @Test func taxPDFExportFetchesFreshAuthenticatedReportAndPreservesDetails() async throws {
        let previousToken = SessionStorage.getAccessToken()
        SessionStorage.saveAccessToken("tax-report-fixture")
        MockURLProtocol.requests = []
        defer {
            MockURLProtocol.requestHandler = nil
            MockURLProtocol.requests = []
            if let previousToken { SessionStorage.saveAccessToken(previousToken) } else { SessionStorage.clearTokens() }
        }
        MockURLProtocol.requestHandler = { request in
            if request.url?.path == "/api/config/maintenance" {
                return MockURLProtocol.jsonResponse(for: request, body: #"{"enabled":false}"#)
            }
            #expect(request.url?.path == "/api/reports/tax-summary")
            #expect(request.httpMethod == "GET")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tax-report-fixture")
            #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
            #expect(query?.first { $0.name == "taxYear" }?.value == "2025")
            #expect(query?.first { $0.name == "_" }?.value?.isEmpty == false)
            return MockURLProtocol.jsonResponse(for: request, body: #"{"success":true,"data":{"taxYear":2025,"totals":{"totalIncomeReceived":"900.25","netSelfEmploymentIncome":"850.25","seTaxableIncome":"800.25","estimatedSelfEmploymentTax":"122.44"},"incomeByClient":[{"clientName":"Fresh report client","orderCount":3,"totalIncomeReceived":"900.25"}]}}"#)
        }
        let api = APIService(baseURL: "https://tax.example.test", session: MockURLProtocol.session())
        let report = try await api.fetchTaxPDFReport(taxYear: 2025)
        #expect(report.summary.taxYear == 2025)
        #expect(report.summary.incomeReceived == 900.25)
        #expect(report.summary.estimatedSelfEmploymentTax == 122.44)
        #expect(report.clients.first?.name == "Fresh report client")
        #expect(report.clients.first?.paid == 900.25)
    }
}

import Foundation
import Observation

struct ReportRequest: Equatable {
    let kind: LedgerReportKind
    let filters: ReportFilters
    let ownerID: String?
}

@MainActor @Observable final class ReportsViewModel {
    nonisolated deinit {}
    private(set) var report: LedgerReport?
    private(set) var reportRevision = UUID()
    private(set) var currentRequest: ReportRequest?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private var revision = UUID()
    private let fetch: (LedgerReportKind, ReportFilters) async throws -> LedgerReport

    init(fetch: ((LedgerReportKind, ReportFilters) async throws -> LedgerReport)? = nil) {
        self.fetch = fetch ?? { try await APIService.shared.fetchBusinessReport(kind: $0, filters: $1) }
    }

    func load(_ request: ReportRequest) async {
        let revision = UUID(); self.revision = revision
        currentRequest = request
        report = nil; errorMessage = nil; isLoading = true
        defer { if self.revision == revision { isLoading = false } }
        guard request.ownerID != nil else { errorMessage = "Sign in to view reports."; return }
        guard request.filters.dateRange() != nil else { errorMessage = ReportError.invalidDateRange.localizedDescription; return }
        do {
            let result = try await fetch(request.kind, request.filters)
            try Task.checkCancellation()
            guard self.revision == revision else { return }
            reportRevision = UUID()
            report = result
        } catch {
            guard self.revision == revision, !RequestCancellation.isCancellation(error) else { return }
            switch error {
            case APIError.unauthorized: errorMessage = "Your session has expired. Please sign in again."
            case APIError.httpError(403, _): errorMessage = "Reports are not available for this account."
            case APIError.httpError(404, _): errorMessage = "This report is not available yet."
            default: errorMessage = "We could not load this report. Please try again."
            }
        }
    }
}

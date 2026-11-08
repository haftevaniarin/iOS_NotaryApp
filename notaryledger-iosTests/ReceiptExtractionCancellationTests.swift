import Foundation
import Testing
@testable import notaryledger_ios

@MainActor
struct ReceiptExtractionCancellationTests {
    private func receipt(_ description: String = "Paper") -> ExtractedExpense {
        ExtractedExpense(description: description, date: "2026-11-07", amount: 12.50,
                         category: "Office supplies", businessUsePercent: 100)
    }

    @Test func cancellingBeforeLoadingPreventsTheOperationFromStarting() async {
        let model = ReceiptExtractionModel()
        var started = false
        let work = model.start {
            started = true
            return receipt()
        }
        model.cancel()
        await work.value
        #expect(work.isCancelled)
        #expect(!started)
        #expect(!model.isExtracting && model.draft == nil && model.errorMessage.isEmpty)
    }

    @Test func closeCancelsActiveWorkAndIgnoresALateSuccessfulResult() async {
        let model = ReceiptExtractionModel()
        let suspended = SuspendedReceipt()
        let work = model.start { try await suspended.load() }
        await suspended.waitUntilStarted()
        #expect(model.isExtracting)
        model.cancel()
        #expect(work.isCancelled && !model.isExtracting)
        // Simulate a provider that still returns after cancellation.
        suspended.finish(.success(receipt()))
        await work.value
        #expect(model.draft == nil && model.errorMessage.isEmpty)
    }

    @Test func closeDoesNotDisplayALateFailure() async {
        let model = ReceiptExtractionModel()
        let suspended = SuspendedReceipt()
        let work = model.start { try await suspended.load() }
        await suspended.waitUntilStarted()
        model.cancel()
        suspended.finish(.failure(URLError(.timedOut)))
        await work.value
        #expect(!model.isExtracting && model.draft == nil && model.errorMessage.isEmpty)
    }

    @Test func cancelledOlderWorkCannotReplaceANewerReceipt() async {
        let model = ReceiptExtractionModel()
        let suspended = SuspendedReceipt()
        let old = model.start { try await suspended.load() }
        await suspended.waitUntilStarted()
        let current = model.start { receipt("New receipt") }
        await current.value
        #expect(model.draft?.description == "New receipt")
        suspended.finish(.success(receipt("Old receipt")))
        await old.value
        #expect(old.isCancelled)
        #expect(model.draft?.description == "New receipt")
        #expect(!model.isExtracting && model.errorMessage.isEmpty)
    }

    @Test func urlSessionCancellationIsSilentAndGenuineErrorsCanBeRetried() async {
        let model = ReceiptExtractionModel()
        let cancelled = model.start { throw URLError(.cancelled) }
        await cancelled.value
        #expect(!model.isExtracting && model.errorMessage.isEmpty && model.draft == nil)
        let failed = model.start { throw APIError.serverError("Could not read this receipt.") }
        await failed.value
        #expect(!model.isExtracting && model.draft == nil)
        #expect(model.errorMessage == "Could not read this receipt.")
        let retry = model.start { receipt() }
        await retry.value
        #expect(model.draft?.description == "Paper")
        #expect(!model.isExtracting && model.errorMessage.isEmpty)
    }
}

@MainActor
private final class SuspendedReceipt {
    private let started = AsyncStream<Void>.makeStream()
    private var continuation: CheckedContinuation<ExtractedExpense, Error>?

    func load() async throws -> ExtractedExpense {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            started.continuation.yield(())
        }
    }

    func waitUntilStarted() async {
        for await _ in started.stream { return }
    }

    func finish(_ result: Result<ExtractedExpense, Error>) {
        continuation?.resume(with: result)
        continuation = nil
        started.continuation.finish()
    }
}

extension ValidationAndAPITests {
    @Test func receiptExtractionCancelsTheInFlightUploadWithoutReturningADraft() async throws {
        let previousToken = SessionStorage.getAccessToken()
        SessionStorage.saveAccessToken("receipt-cancellation-fixture")
        MockURLProtocol.requests = []
        defer {
            MockURLProtocol.requestHandler = nil
            MockURLProtocol.requests = []
            if let previousToken { SessionStorage.saveAccessToken(previousToken) } else { SessionStorage.clearTokens() }
        }
        let api = APIService(baseURL: "https://receipt.example.test", session: MockURLProtocol.session())
        let work = Task {
            try await api.extractExpense(MultipartFile(fieldName: "file", fileName: "receipt.jpg",
                                                      mimeType: "image/jpeg", data: Data([0xff, 0xd8, 0xff, 0xd9])))
        }
        MockURLProtocol.requestHandler = { request in
            if request.url?.path == "/api/expenses/extract" {
                work.cancel()
                return MockURLProtocol.jsonResponse(for: request, body: #"{"draft":{"description":"Paper","amount":12.5}}"#)
            }
            return MockURLProtocol.jsonResponse(for: request, body: #"{"enabled":false}"#)
        }
        do {
            _ = try await work.value
            Issue.record("Cancelled extraction must not return a receipt draft")
        } catch { #expect(RequestCancellation.isCancellation(error)) }
        #expect(work.isCancelled)
        #expect(MockURLProtocol.requests.contains { $0.url?.path == "/api/expenses/extract" })
    }
}

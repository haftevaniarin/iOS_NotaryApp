import Foundation
import Combine

@MainActor
final class ReceiptExtractionModel: ObservableObject {
    @Published private(set) var isExtracting = false
    @Published var errorMessage = ""
    @Published var draft: ExtractedExpense?
    private var task: Task<Void, Never>?
    private var requestID: UUID?

    @discardableResult
    func start(_ load: @escaping @MainActor () async throws -> ExtractedExpense) -> Task<Void, Never> {
        cancel()
        draft = nil
        let id = UUID()
        requestID = id
        isExtracting = true
        let work = Task { [weak self] in
            do {
                try Task.checkCancellation()
                let result = try await load()
                try Task.checkCancellation()
                guard let self, self.requestID == id else { return }
                self.draft = result
            } catch {
                guard let self, self.requestID == id else { return }
                if !Task.isCancelled && !RequestCancellation.isCancellation(error) {
                    self.errorMessage = error.localizedDescription
                }
            }
            guard let self, self.requestID == id else { return }
            self.isExtracting = false
            self.requestID = nil
            self.task = nil
        }
        task = work
        return work
    }

    func cancel() {
        requestID = nil
        task?.cancel()
        task = nil
        isExtracting = false
        errorMessage = ""
    }
}

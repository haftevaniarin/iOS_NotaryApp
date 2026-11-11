import SwiftUI

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    var onComplete: (@MainActor (UIActivity.ActivityType?, Bool) -> Void)? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        vc.completionWithItemsHandler = { activity, completed, _, error in
            let succeeded = completed && error == nil
            Task { @MainActor in onComplete?(activity, succeeded) }
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct InvoiceShareSheet: View {
    let item: ShareURL
    let orderIDs: [String]
    let ownerID: String?
    var onRecorded: () -> Void = {}
    var onError: (String) -> Void = { _ in }
    var body: some View {
        ShareSheet(activityItems: [item.url]) { activity, completed in
            guard completed, let channel = InvoiceSendTracking.channel(for: activity) else { return }
            Task {
                do { try await InvoiceSendTracking.record(item: item, orderIDs: orderIDs, ownerID: ownerID, channel: channel); onRecorded() }
                catch { onError("The invoice was shared, but its send could not be recorded. Use Mark Invoice as Sent to retry.") }
            }
        }
    }
}

enum InvoiceSendTracking {
    static func channel(for activity: UIActivity.ActivityType?) -> String? {
        // Saving, copying, printing, or canceling never counts as sending.
        switch activity { case .mail: "mail"; case .message: "message"; default: nil }
    }
    static func record(item: ShareURL, orderIDs: [String], ownerID: String?, channel: String = "confirmed") async throws {
        guard let ownerID, SessionStorage.getCurrentUser()?.id == ownerID else { throw APIError.unauthorized }
        try await APIService.shared.recordInvoiceSent(id: item.id, orderIDs: orderIDs, channel: channel)
    }
}

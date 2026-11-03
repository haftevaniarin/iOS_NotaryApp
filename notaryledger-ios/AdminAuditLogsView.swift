import SwiftUI

struct AdminAuditLogsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var action = ""
    @State private var logs: [AuditEntry] = []
    @State private var page = 1
    @State private var total = 0
    @State private var busy = false
    @State private var error = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NLSpacing.lg) {
                ScreenTitleBlock(title: "Admin Audit Logs", subtitle: "Admin-only activity review.")
                if appState.currentUser?.canAccessAdminAudit != true {
                    BannerView(kind: .error, message: "This view is restricted to administrator accounts.")
                } else {
                    NLTextField(title: "Action filter (exact action)", text: $action)
                        .textInputAutocapitalization(.never)
                    Button("Apply Filter") { page = 1; Task { await load() } }.buttonStyle(SecondaryButtonStyle()).disabled(busy)
                    ErrorBanner(message: error)
                    if busy { ProgressView("Loading audit logs...") }
                    if logs.isEmpty && !busy && error.isEmpty {
                        EmptyStateView(title: "No audit logs found", systemImage: "checklist.checked", message: "Adjust the action filter or refresh.")
                    }
                    ForEach(logs) { log in
                        NLCard {
                            VStack(alignment: .leading, spacing: NLSpacing.sm) {
                                Text(log.action).font(NLTypography.cardTitle).foregroundColor(NLColor.navy)
                                DetailRow(label: "Date", value: log.createdAt)
                                DetailRow(label: "Actor", value: log.actorUserId ?? "System")
                                DetailRow(label: "Target", value: [log.entityType, log.entityId].compactMap { $0 }.joined(separator: " · "))
                                DetailRow(label: "Outcome", value: log.outcome)
                                DetailRow(label: "Severity", value: log.severity)
                                if let requestId = log.requestId { DetailRow(label: "Request", value: requestId) }
                            }
                        }
                    }
                    HStack {
                        Button("Previous") { page -= 1; Task { await load() } }.disabled(page <= 1 || busy)
                        Spacer()
                        Text("Page \(page) · \(total) records").font(NLTypography.caption)
                        Spacer()
                        Button("Next") { page += 1; Task { await load() } }.disabled(page * 25 >= total || busy)
                    }
                }
            }.nlScreenPadding()
        }.background(ParchmentBackground()).task { await load() }.refreshable { await load() }
            .onChange(of: appState.currentUser?.canAccessAdminAudit) { _, allowed in if allowed != true { logs = []; total = 0 } }
    }
    private func load() async {
        guard appState.currentUser?.canAccessAdminAudit == true, !busy else { return }
        busy = true; error = ""; logs = []
        defer { busy = false }
        do {
            let result = try await APIService.shared.fetchAuditLogs(page: page, action: action.trimmingCharacters(in: .whitespacesAndNewlines))
            guard appState.currentUser?.canAccessAdminAudit == true else { return }
            logs = result.items; total = result.pagination.total
        } catch { self.error = error.localizedDescription }
    }
}

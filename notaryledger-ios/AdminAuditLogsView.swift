import SwiftUI

struct AuditLogItem: Identifiable {
    let id = UUID()
    let event: String
    let actor: String
    let date: String
    let target: String
}

struct AdminAuditLogsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var searchText = ""
    @State private var logs: [AuditLogItem] = [
        AuditLogItem(event: "Account login", actor: "System", date: "Today", target: "Current session"),
        AuditLogItem(event: "Ledger refresh", actor: "System", date: "Today", target: "Orders and expenses")
    ]

    private var filteredLogs: [AuditLogItem] {
        logs.filter { log in
            searchText.isEmpty || "\(log.event) \(log.actor) \(log.target)".lowercased().contains(searchText.lowercased())
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NLSpacing.lg) {
                ScreenTitleBlock(title: "Admin Audit Logs", subtitle: "Admin-only activity review.")

                if appState.currentUser?.canAccessAdminAudit != true {
                    BannerView(kind: .error, message: "This view is restricted to administrator accounts.")
                } else {
                    NLTextField(title: "Search audit logs", text: $searchText)

                    if filteredLogs.isEmpty {
                        EmptyStateView(title: "No audit logs found", systemImage: "checklist.checked", message: "Adjust search filters to review account activity.")
                    } else {
                        VStack(spacing: NLSpacing.md) {
                            ForEach(filteredLogs) { log in
                                NLCard {
                                    VStack(alignment: .leading, spacing: NLSpacing.sm) {
                                        HStack {
                                            Text(log.event)
                                                .font(.headline)
                                                .foregroundColor(NLColor.navy)
                                            Spacer()
                                            Text(log.date)
                                                .font(.caption.weight(.semibold))
                                                .foregroundColor(NLColor.brass)
                                        }
                                        DetailRow(label: "Actor", value: log.actor)
                                        DetailRow(label: "Target", value: log.target)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(NLSpacing.lg)
        }
        .background(ParchmentBackground())
    }
}

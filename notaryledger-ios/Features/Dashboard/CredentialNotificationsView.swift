import SwiftUI

struct CredentialNotificationsView: View {
    @ObservedObject var credentials: CredentialsEditorModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let notifications = CredentialNotification.make(credentials: credentials.saved, today: context.date)
                ScrollView {
                    VStack(alignment: .leading, spacing: NLSpacing.md) {
                        if !credentials.error.isEmpty {
                            ErrorBanner(message: credentials.error)
                            Button("Retry loading credentials") { Task { await credentials.reload() } }
                                .buttonStyle(SecondaryButtonStyle())
                        }
                        if credentials.isLoading && credentials.saved == nil {
                            ProgressView("Loading notifications…").frame(maxWidth: .infinity)
                        } else if credentials.saved != nil && notifications.isEmpty {
                            ContentUnavailableView("No notifications at the moment", systemImage: "checkmark.seal",
                                                   description: Text("New updates and reminders will appear here."))
                        }
                        ForEach(notifications) { notification in
                            NavigationLink {
                                ScrollView { CredentialsEditor(model: credentials).nlScreenPadding() }
                                    .background(ParchmentBackground()).navigationTitle("Credentials")
                            } label: {
                                NLCard {
                                    HStack(spacing: NLSpacing.md) {
                                        Image(systemName: notification.status == .expired ? "exclamationmark.triangle.fill" : "clock")
                                            .foregroundStyle(notification.status == .expired ? NLColor.danger : NLColor.warning)
                                            .accessibilityHidden(true)
                                        VStack(alignment: .leading, spacing: NLSpacing.xs) {
                                            Text(notification.title).font(NLTypography.bodyStrong).foregroundStyle(NLColor.navy)
                                            Text(notification.status.badgeTitle ?? "").font(NLTypography.caption)
                                                .foregroundStyle(notification.status == .expired ? NLColor.danger : NLColor.warning)
                                            Text(notification.message).font(NLTypography.caption).foregroundStyle(NLColor.muted)
                                        }.frame(maxWidth: .infinity, alignment: .leading)
                                        Image(systemName: "chevron.right").foregroundStyle(NLColor.muted).accessibilityHidden(true)
                                    }.fixedSize(horizontal: false, vertical: true)
                                }
                            }.buttonStyle(.plain).accessibilityIdentifier("credential-notification-\(notification.id.rawValue)")
                        }
                    }.nlScreenPadding()
                }.background(ParchmentBackground())
                    .refreshable { await credentials.reload() }
            }
            .navigationTitle("Notifications").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
    }
}

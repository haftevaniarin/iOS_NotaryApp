import SwiftUI
import Combine

struct SupportContactDraft {
    var name = ""
    var email = ""
    var topic = LegalSupportContactModel.topics[0]
    var subject = ""
    var message = ""
}

@MainActor
final class LegalSupportContactModel: ObservableObject {
    static let topics = ["Account access", "Billing", "Product support", "Privacy request", "Bug report"]
    static let sentMessage = "Support request sent to \(LegalDocumentKind.supportEmail). We'll follow up by email."
    @Published var draft = SupportContactDraft()
    @Published private(set) var fieldErrors: [String: String] = [:]
    @Published private(set) var error = ""
    @Published private(set) var success = ""
    @Published private(set) var isSubmitting = false
    private let sourcePage: String
    private let send: (SupportContactRequest) async throws -> Void

    nonisolated deinit {}

    init(sourcePage: String, send: ((SupportContactRequest) async throws -> Void)? = nil) {
        self.sourcePage = sourcePage
        self.send = send ?? { try await APIService.shared.contactSupport($0) }
    }

    func prefill(_ user: AuthUser?) {
        guard let user else { return }
        if draft.name.isEmpty { draft.name = user.fullName }
        if draft.email.isEmpty { draft.email = user.email }
    }

    func update(_ keyPath: WritableKeyPath<SupportContactDraft, String>, field: String, value: String) {
        draft[keyPath: keyPath] = value
        fieldErrors[field] = nil
        error = ""
        success = ""
    }

    func submit() async {
        guard !isSubmitting else { return }
        fieldErrors = [:]
        error = ""
        success = ""
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = draft.email.trimmingCharacters(in: .whitespacesAndNewlines)
        let subject = draft.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = draft.message.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { fieldErrors["name"] = "Please enter your name." }
        if email.isEmpty { fieldErrors["email"] = "Please enter your email." }
        else if !email.contains("@") || !email.contains(".") { fieldErrors["email"] = "Please enter a valid email address." }
        if subject.isEmpty { fieldErrors["subject"] = "Please enter a subject." }
        if message.isEmpty { fieldErrors["message"] = "Please enter a message." }
        else if message.utf16.count < 10 { fieldErrors["message"] = "Please add a little more detail." }
        guard fieldErrors.isEmpty else { return }

        let topic = Self.topics.contains(draft.topic) ? draft.topic : Self.topics[0]
        // The API accepts these canonical topics; keep the web labels in the picker.
        let apiTopic = ["Product support": "other", "Bug report": "technical"][topic] ?? topic
        let request = SupportContactRequest(name: name, email: email, topic: apiTopic,
                                            subject: subject, message: message, sourcePage: sourcePage)
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await send(request)
            success = Self.sentMessage
            draft.topic = Self.topics[0]
            draft.subject = ""
            draft.message = ""
        } catch let failure as SupportContactFailure {
            fieldErrors = failure.fieldErrors
            error = failure.message
        } catch {
            self.error = error.localizedDescription.isEmpty
                ? "Could not send your support request. Please try again." : error.localizedDescription
        }
    }
}

struct SupportContactFailure: LocalizedError {
    let message: String
    let fieldErrors: [String: String]
    var errorDescription: String? { message }
}

struct LegalSupportContactForm: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var model: LegalSupportContactModel

    init(sourcePage: String) {
        _model = StateObject(wrappedValue: LegalSupportContactModel(sourcePage: sourcePage))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ErrorBanner(message: model.error)
            BannerView(kind: .success, message: model.success)
            field("name") {
                NLTextField(title: "Name", text: binding(\.name, field: "name"))
                    .textContentType(.name)
            }
            field("email") {
                NLTextField(title: "Email", text: binding(\.email, field: "email"), keyboardType: .emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            field("topic") {
                NLSelectField(title: "Topic", selection: binding(\.topic, field: "topic"), value: model.draft.topic) {
                    ForEach(LegalSupportContactModel.topics, id: \.self) { Text($0).tag($0) }
                }
            }
            field("subject") {
                NLTextField(title: "Subject", text: binding(\.subject, field: "subject"))
            }
            field("message") {
                NLTextArea(title: "Message", text: binding(\.message, field: "message"), minimumHeight: 130)
            }
            Button(model.isSubmitting ? "Sending..." : "Send support request") {
                Task { await model.submit() }
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .disabled(model.isSubmitting)
        .onAppear { model.prefill(appState.currentUser) }
        .onChange(of: appState.currentUser) { _, user in model.prefill(user) }
    }

    private func binding(_ keyPath: WritableKeyPath<SupportContactDraft, String>, field: String) -> Binding<String> {
        Binding(get: { model.draft[keyPath: keyPath] },
                set: { model.update(keyPath, field: field, value: $0) })
    }

    private func field<Content: View>(_ key: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            content()
            if let error = model.fieldErrors[key] {
                Text(error).font(NLTypography.caption).foregroundStyle(NLColor.danger)
            }
        }
    }
}

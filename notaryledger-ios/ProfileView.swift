import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var appState: AppState
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var errorMessage = ""
    @State private var successMessage = ""
    @State private var showSupport = false
    @State private var showDeleteAccount = false
    @State private var isSavingProfile = false
    @State private var isRequestingExport = false
    @State private var commissionNumber = ""
    @State private var commissionExpiration = ""
    @State private var bondExpiration = ""
    @State private var insuranceExpiration = ""
    @State private var deletionRequested = false

    var body: some View {
        ZStack {
            ParchmentBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: NLSpacing.lg) {
                    ScreenTitleBlock(title: "Profile", subtitle: appState.currentUser?.email ?? "Account details")
                    BannerView(kind: .success, message: successMessage)
                    ErrorBanner(message: errorMessage)

                    NLCard {
                        VStack(alignment: .leading, spacing: NLSpacing.md) {
                            Text("Profile")
                                .font(.headline)
                                .foregroundColor(NLColor.navy)
                            NLTextField(title: "First name", text: $firstName)
                            NLTextField(title: "Last name", text: $lastName)
                            DetailRow(label: "Email", value: appState.currentUser?.email ?? "-")
                    Button(isSavingProfile ? "Saving..." : "Update Profile") {
                        Task { await saveProfile() }
                    }
                            .buttonStyle(PrimaryButtonStyle())
                    .disabled(isSavingProfile)
                }
                    }

                    NLCard {
                        VStack(alignment: .leading, spacing: NLSpacing.md) {
                            Text("Credentials")
                                .font(.headline)
                                .foregroundColor(NLColor.navy)
                            NLTextField(title: "Commission number", text: $commissionNumber)
                            NLTextField(title: "Commission expiration", text: $commissionExpiration)
                            NLTextField(title: "Bond expiration", text: $bondExpiration)
                            NLTextField(title: "E&O insurance expiration", text: $insuranceExpiration)
                            BannerView(kind: .warning, message: "Keep credential dates current so dashboard risk banners stay actionable.")
                        }
                    }

                    NLCard {
                        VStack(alignment: .leading, spacing: NLSpacing.md) {
                            Text("Password")
                                .font(.headline)
                                .foregroundColor(NLColor.navy)
                            NavigationLink {
                                ChangePasswordView()
                            } label: {
                                Label("Change Password", systemImage: "key")
                            }
                            .buttonStyle(SecondaryButtonStyle())
                        }
                    }

                    NLCard {
                        VStack(alignment: .leading, spacing: NLSpacing.md) {
                            Text("Data & Privacy")
                                .font(.headline)
                                .foregroundColor(NLColor.navy)
                            Button(isRequestingExport ? "Requesting..." : "Export My Data") {
                                Task { await requestExport() }
                            }
                            .buttonStyle(SecondaryButtonStyle())
                            .disabled(isRequestingExport)

                            if deletionRequested {
                                BannerView(kind: .warning, message: "Account deletion has been requested.")
                                Button("Cancel Deletion Request") {
                                    Task { await cancelDeletionRequest() }
                                }
                                .buttonStyle(SecondaryButtonStyle())
                            } else {
                                Button(role: .destructive) {
                                    showDeleteAccount = true
                                } label: {
                                    Label("Request Account Deletion", systemImage: "trash")
                                }
                            }
                        }
                    }

                    NLCard {
                        VStack(alignment: .leading, spacing: NLSpacing.md) {
                            Text("Support")
                                .font(.headline)
                                .foregroundColor(NLColor.navy)
                            Button {
                                showSupport = true
                            } label: {
                                Label("Contact Support", systemImage: "envelope")
                            }
                            .buttonStyle(SecondaryButtonStyle())

                            Button("Sign Out") {
                                Task { await appState.signOut() }
                            }
                            .buttonStyle(SecondaryButtonStyle())
                        }
                    }
                }
                .padding(NLSpacing.lg)
            }
        }
        .sheet(isPresented: $showSupport) {
            NavigationStack {
                SupportContactView(sourcePage: "Profile")
            }
        }
        .sheet(isPresented: $showDeleteAccount) {
            DeleteConfirmationSheet(
                title: "Request Account Deletion",
                message: "Submit a request to delete your Notary Ledger account and ledger data?"
            ) {
                Task { await deleteAccount() }
            }
        }
        .onAppear {
            firstName = appState.currentUser?.displayFirstName ?? ""
            lastName = appState.currentUser?.displayLastName ?? ""
        }
    }

    private func saveProfile() async {
        errorMessage = ""
        successMessage = ""
        isSavingProfile = true
        defer { isSavingProfile = false }
        do {
            let user = try await APIService.shared.updateProfile(
                firstName: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
                lastName: lastName.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            appState.currentUser = user
            successMessage = "Profile updated."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func requestExport() async {
        errorMessage = ""
        successMessage = ""
        isRequestingExport = true
        defer { isRequestingExport = false }
        do {
            try await APIService.shared.requestDataExport()
            successMessage = "Data export requested."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteAccount() async {
        do {
            try await APIService.shared.requestAccountDeletion()
            deletionRequested = true
            successMessage = "Account deletion requested."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func cancelDeletionRequest() async {
        errorMessage = ""
        successMessage = ""
        do {
            try await APIService.shared.cancelAccountDeletion()
            deletionRequested = false
            successMessage = "Account deletion request canceled."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ChangePasswordView: View {
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var errorMessage = ""
    @State private var successMessage = ""
    @State private var isSaving = false

    var body: some View {
        ZStack {
            ParchmentBackground()
            Form {
                Section("Password") {
                    SecureField("Current password", text: $currentPassword)
                    SecureField("New password", text: $newPassword)
                    SecureField("Confirm new password", text: $confirmPassword)
                }

                if !successMessage.isEmpty {
                    Section {
                        Text(successMessage)
                            .foregroundColor(NLColor.navy)
                    }
                }
                if !errorMessage.isEmpty {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    }
                }

                Section {
                    Button(isSaving ? "Saving..." : "Change Password") {
                        Task { await save() }
                    }
                    .disabled(isSaving)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Change Password")
    }

    private func save() async {
        errorMessage = ""
        successMessage = ""
        guard !currentPassword.isEmpty else {
            errorMessage = "Enter your current password."
            return
        }
        if let validationMessage = PasswordValidation.message(for: newPassword) {
            errorMessage = validationMessage
            return
        }
        guard newPassword == confirmPassword else {
            errorMessage = "Passwords do not match."
            return
        }

        isSaving = true
        defer { isSaving = false }
        do {
            try await APIService.shared.changePassword(currentPassword: currentPassword, newPassword: newPassword)
            currentPassword = ""
            newPassword = ""
            confirmPassword = ""
            successMessage = "Password changed."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct SupportContactView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    let sourcePage: String

    @State private var name = ""
    @State private var email = ""
    @State private var topic = "Account"
    @State private var subject = ""
    @State private var message = ""
    @State private var errorMessage = ""
    @State private var successMessage = ""
    @State private var isSubmitting = false

    private let topics = ["Account", "Billing", "Invoices", "Tax Summary", "Technical Issue", "Other"]

    var body: some View {
        ZStack {
            ParchmentBackground()
            Form {
                Section("Contact") {
                    TextField("Name", text: $name)
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Picker("Topic", selection: $topic) {
                        ForEach(topics, id: \.self) { topic in
                            Text(topic).tag(topic)
                        }
                    }
                }

                Section("Message") {
                    TextField("Subject", text: $subject)
                    TextEditor(text: $message)
                        .frame(minHeight: 120)
                }

                if !successMessage.isEmpty {
                    Section {
                        Text(successMessage)
                            .foregroundColor(NLColor.navy)
                    }
                }
                if !errorMessage.isEmpty {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Contact Support")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(isSubmitting ? "Sending..." : "Send") {
                    Task { await submit() }
                }
                .disabled(isSubmitting)
            }
        }
        .onAppear {
            if let user = appState.currentUser {
                name = user.fullName
                email = user.email
            }
        }
    }

    private func submit() async {
        errorMessage = ""
        successMessage = ""
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Enter your name."
            return
        }
        guard email.contains("@") else {
            errorMessage = "Enter a valid email address."
            return
        }
        guard !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Enter a subject."
            return
        }
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Enter a message."
            return
        }

        let payload = SupportContactRequest(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            topic: topic,
            subject: subject.trimmingCharacters(in: .whitespacesAndNewlines),
            message: message.trimmingCharacters(in: .whitespacesAndNewlines),
            sourcePage: sourcePage
        )

        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await APIService.shared.contactSupport(payload)
            successMessage = "Support request sent."
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

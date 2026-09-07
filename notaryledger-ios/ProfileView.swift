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

    var body: some View {
        ZStack {
            ParchmentBackground()
            List {
                if !successMessage.isEmpty {
                    Section {
                        Text(successMessage)
                            .foregroundColor(NLColor.navy)
                    }
                }
                if !errorMessage.isEmpty {
                    Section {
                        ErrorBanner(message: errorMessage)
                    }
                    .listRowBackground(Color.clear)
                }

                Section("Profile") {
                    TextField("First name", text: $firstName)
                    TextField("Last name", text: $lastName)
                    Button(isSavingProfile ? "Saving..." : "Update Profile") {
                        Task { await saveProfile() }
                    }
                    .disabled(isSavingProfile)
                }

                Section("Security") {
                    NavigationLink("Change Password") {
                        ChangePasswordView()
                    }
                }

                Section("Support") {
                    Button("Contact Support") {
                        showSupport = true
                    }
                }

                Section("Account") {
                    Button(isRequestingExport ? "Requesting..." : "Export My Data") {
                        Task { await requestExport() }
                    }
                    .disabled(isRequestingExport)

                    Button(role: .destructive) {
                        showDeleteAccount = true
                    } label: {
                        Text("Delete Account")
                    }

                    Button("Sign Out") {
                        appState.signOut()
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Profile")
        .sheet(isPresented: $showSupport) {
            NavigationStack {
                SupportContactView(sourcePage: "Profile")
            }
        }
        .sheet(isPresented: $showDeleteAccount) {
            DeleteConfirmationSheet(
                title: "Delete Account",
                message: "Delete your Notary Ledger account and ledger data?"
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
            try await APIService.shared.deleteAccount()
            appState.signOut()
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

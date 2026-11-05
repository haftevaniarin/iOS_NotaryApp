import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ProfileView: View {
    @EnvironmentObject private var appState: AppState
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var startAddress = ""
    @State private var errorMessage = ""
    @State private var successMessage = ""
    @State private var showSupport = false
    @State private var showDeleteAccount = false
    @State private var isSavingProfile = false
    @State private var isRequestingExport = false
    @State private var deletion: DeletionRequest?
    @State private var deletionLoaded = false
    @State private var deletionBusy = false
    @State private var exportItem: ShareURL?
    @State private var photoItem: PhotosPickerItem?
    @State private var preview: Data?
    @State private var photoBusy = false
    @State private var scanNotice = ""
    @State private var photoTask: Task<Void, Never>?

    var body: some View {
        let storedPhotoURL = appState.currentUser?.profilePhotoUrl
        ZStack {
            ParchmentBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: NLSpacing.lg) {
                    ScreenTitleBlock(title: "Profile", subtitle: appState.currentUser?.email ?? "Account details")
                    BannerView(kind: .success, message: successMessage)
                    ErrorBanner(message: errorMessage)
                    NLCard {
                        VStack(alignment: .leading, spacing: NLSpacing.md) {
                            HStack(spacing: NLSpacing.md) {
                                PhotosPicker(selection: $photoItem, matching: .images) {
                                    ZStack {
                                        Circle().fill(NLColor.brass.opacity(0.15))
                                        Text(initials).font(NLFonts.serif(20)).foregroundColor(NLColor.navy)
                                        if let preview, let image = UIImage(data: preview) {
                                            Image(uiImage: image).resizable().scaledToFill()
                                        } else if let value = storedPhotoURL, let url = URL(string: value) {
                                            AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Color.clear }
                                        }
                                    }
                                    .frame(width: 52, height: 52).clipShape(Circle())
                                }
                                .accessibilityLabel("Choose profile photo")
                                .disabled(photoBusy || appState.currentUser?.profilePhotoUpload != nil)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(appState.currentUser?.fullName ?? "Profile").font(NLFonts.serif(19)).foregroundColor(NLColor.navy)
                                    Text("Tap your avatar to change your photo").font(NLTypography.caption).foregroundColor(NLColor.muted)
                                }
                            }
                            if preview != nil {
                                HStack {
                                    Button("Upload Photo") { Task { await uploadPhoto() } }.disabled(photoBusy)
                                    Button("Discard") { preview = nil; photoItem = nil }.disabled(photoBusy)
                                }
                            } else if let upload = appState.currentUser?.profilePhotoUpload {
                                Text(scanNotice.isEmpty ? "Photo is being scanned. Your current photo stays visible." : scanNotice).font(NLTypography.caption)
                                Button("Cancel Photo Upload") { Task { await photoAction(uploadId: upload.id) } }.disabled(photoBusy)
                            } else if appState.currentUser?.profilePhotoUrl != nil {
                                Button("Remove Photo", role: .destructive) { Task { await photoAction() } }.disabled(photoBusy)
                            }
                            if photoBusy { ProgressView() }
                            NLTextField(title: "First name", text: $firstName)
                            NLTextField(title: "Last name", text: $lastName)
                            NLTextField(title: "Default start address", text: $startAddress)
                            DetailRow(label: "Email", value: appState.currentUser?.email ?? "-")
                            Button(isSavingProfile ? "Saving..." : "Update Profile") { Task { await saveProfile() } }
                                .buttonStyle(PrimaryButtonStyle()).disabled(isSavingProfile)
                        }
                    }
                    CredentialsEditor()
                    NLCard {
                        VStack(alignment: .leading, spacing: NLSpacing.md) {
                            Text("Password").font(NLTypography.cardTitle).foregroundColor(NLColor.navy)
                            NavigationLink { ChangePasswordView() } label: { Label("Change Password", systemImage: "key") }
                                .buttonStyle(SecondaryButtonStyle())
                        }
                    }
                    NLCard {
                        VStack(alignment: .leading, spacing: NLSpacing.md) {
                            Text("Data & Privacy").font(NLTypography.cardTitle).foregroundColor(NLColor.navy)
                            Button(isRequestingExport ? "Preparing..." : "Export My Data") { Task { await requestExport() } }
                                .buttonStyle(SecondaryButtonStyle()).disabled(isRequestingExport)
                            if let deletion, deletion.isActive {
                                BannerView(kind: .warning, message: "Deletion status: \(deletion.status.replacingOccurrences(of: "_", with: " "))")
                                DetailRow(label: "Requested", value: deletion.requestedAt)
                                if let scheduled = deletion.scheduledDeletionAt { DetailRow(label: "Scheduled", value: scheduled) }
                                Button("Cancel Deletion Request") { Task { await changeDeletion(cancel: true) } }
                                    .buttonStyle(SecondaryButtonStyle()).disabled(deletionBusy)
                            } else {
                                Button("Request Account Deletion", role: .destructive) { showDeleteAccount = true }
                                    .disabled(!deletionLoaded || deletionBusy)
                            }
                            if !deletionLoaded { Button("Reload deletion status") { Task { await loadDeletion() } } }
                        }
                    }
                    NLCard {
                        VStack(alignment: .leading, spacing: NLSpacing.md) {
                            Text("Support").font(NLTypography.cardTitle).foregroundColor(NLColor.navy)
                            Button { showSupport = true } label: { Label("Contact Support", systemImage: "envelope") }.buttonStyle(SecondaryButtonStyle())
                            Button("Sign Out") { Task { await appState.signOut() } }.buttonStyle(SecondaryButtonStyle())
                        }
                    }
                }.nlScreenPadding()
            }
        }
        .sheet(isPresented: $showSupport) { NavigationStack { SupportContactView(sourcePage: "Profile") } }
        .sheet(item: $exportItem) { ShareSheet(activityItems: [$0.url]) }
        .sheet(isPresented: $showDeleteAccount) {
            DeleteConfirmationSheet(title: "Request Account Deletion", message: "Submit a request to delete your Notary Ledger account and ledger data?") { Task { await changeDeletion(cancel: false) } }
        }
        .task {
            populate()
            do { appState.currentUser = try await APIService.shared.fetchCurrentUser(); populate() }
            catch { errorMessage = error.localizedDescription }
            await loadDeletion()
        }
        .onChange(of: photoItem) { _, item in
            photoTask?.cancel()
            photoTask = Task { await selectPhoto(item) }
        }
        .onDisappear { photoTask?.cancel() }
        .task(id: appState.currentUser?.profilePhotoUpload?.id) { await pollPhoto() }
    }
    private var initials: String { [firstName, lastName].compactMap { $0.first.map(String.init) }.joined().uppercased() }
    private func populate() {
        firstName = appState.currentUser?.displayFirstName ?? ""
        lastName = appState.currentUser?.displayLastName ?? ""
        startAddress = appState.currentUser?.defaultStartAddress ?? ""
    }
    private func saveProfile() async {
        errorMessage = ""; successMessage = ""
        guard !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              firstName.count <= 100, lastName.count <= 100, startAddress.count <= 255 else { errorMessage = "Enter first and last names up to 100 characters and an address up to 255 characters."; return }
        isSavingProfile = true
        defer { isSavingProfile = false }
        do {
            appState.currentUser = try await APIService.shared.updateProfile(firstName: firstName.trimmingCharacters(in: .whitespacesAndNewlines), lastName: lastName.trimmingCharacters(in: .whitespacesAndNewlines), defaultStartAddress: startAddress.trimmingCharacters(in: .whitespacesAndNewlines))
            successMessage = "Profile updated."
        } catch { errorMessage = error.localizedDescription }
    }
    private func requestExport() async {
        errorMessage = ""; successMessage = ""; isRequestingExport = true
        defer { isRequestingExport = false }
        do { exportItem = ShareURL(url: try await APIService.shared.requestDataExport()) }
        catch { errorMessage = error.localizedDescription }
    }
    private func loadDeletion() async {
        do { deletion = try await APIService.shared.fetchAccountDeletion().deletionRequest; deletionLoaded = true }
        catch { errorMessage = error.localizedDescription }
    }
    private func changeDeletion(cancel: Bool) async {
        errorMessage = ""; successMessage = ""; deletionBusy = true
        defer { deletionBusy = false }
        do {
            let response = try await (cancel ? APIService.shared.cancelAccountDeletion() : APIService.shared.requestAccountDeletion())
            guard let request = response.deletionRequest, cancel ? request.status == "CANCELLED" : request.isActive else { throw APIError.invalidResponse }
            deletion = request
            successMessage = cancel ? "Account deletion request canceled." : "Account deletion requested."
        } catch { errorMessage = error.localizedDescription; await loadDeletion() }
    }
    private func selectPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        errorMessage = ""; successMessage = ""
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { throw APIError.invalidResponse }
            try Task.checkCancellation()
            let mime = item.supportedContentTypes.first?.preferredMIMEType ?? ""
            try UploadValidation.validate(data: data, mimeType: mime, photo: true)
            guard UIImage(data: data) != nil else { throw APIError.serverError("The selected image could not be read.") }
            preview = data
        } catch is CancellationError { } catch { preview = nil; errorMessage = error.localizedDescription }
    }
    private func applyPhoto(_ response: PhotoResponse) {
        guard var user = appState.currentUser else { return }
        if response.upload?.isPending != true { user.profilePhotoUrl = response.profilePhotoUrl }
        user.profilePhotoUpload = response.upload?.isPending == true ? response.upload : nil
        appState.currentUser = user
        SessionStorage.saveCurrentUser(user)
    }
    private func uploadPhoto() async {
        guard let preview else { return }
        errorMessage = ""; successMessage = ""; photoBusy = true
        defer { photoBusy = false }
        do {
            let mime = photoItem?.supportedContentTypes.first?.preferredMIMEType ?? ""
            let ext = mime == "image/png" ? "png" : mime == "image/webp" ? "webp" : "jpg"
            let response = try await APIService.shared.uploadProfilePhoto(MultipartFile(fieldName: "photo", fileName: "photo.\(ext)", mimeType: mime, data: preview))
            applyPhoto(response); self.preview = nil; photoItem = nil
            if response.upload?.isPending != true { successMessage = "Profile photo updated." }
        } catch { errorMessage = error.localizedDescription }
    }
    private func photoAction(uploadId: String? = nil) async {
        errorMessage = ""; successMessage = ""; photoBusy = true
        defer { photoBusy = false }
        do {
            let result = try await APIService.shared.photoAction(uploadId: uploadId, method: "DELETE")
            applyPhoto(result)
            successMessage = uploadId == nil ? "Profile photo removed." : result.upload?.status == "COMPLETED" ? "Profile photo updated." : "Photo upload canceled."
        }
        catch { errorMessage = error.localizedDescription }
    }
    private func pollPhoto() async {
        guard let id = appState.currentUser?.profilePhotoUpload?.id else { return }
        let owner = appState.currentUser?.id
        do {
            let deadline = Date().addingTimeInterval(15 * 60)
            var failures = 0
            while Date() < deadline {
                try await Task.sleep(for: .seconds(failures == 0 ? 3 : min(30, 3 * pow(2, Double(failures)))))
                let response: PhotoResponse
                do {
                    response = try await APIService.shared.photoAction(uploadId: id, method: "GET")
                    failures = 0; scanNotice = ""
                } catch {
                    if Task.isCancelled { return }
                    let retry: Bool
                    if case APIError.httpError(let status, _) = error { retry = status == 429 || status >= 500 }
                    else { retry = error is URLError }
                    guard retry else { throw error }
                    failures += 1; scanNotice = "Photo scan status is temporarily unavailable. Retrying…"
                    continue
                }
                guard appState.currentUser?.id == owner, appState.currentUser?.profilePhotoUpload?.id == id else { return }
                guard let upload = response.upload, upload.id == id else { throw APIError.invalidResponse }
                if ["FAILED", "REJECTED"].contains(upload.status) {
                    applyPhoto(response)
                    throw APIError.serverError(upload.error?.message ?? "The photo could not be accepted.")
                }
                guard upload.isPending || ["COMPLETED", "CANCELLED"].contains(upload.status) else { throw APIError.invalidResponse }
                applyPhoto(response)
                if !upload.isPending { successMessage = upload.status == "COMPLETED" ? "Profile photo updated." : "Photo upload canceled."; return }
            }
            throw APIError.serverError("Photo scanning is taking longer than expected. Reopen Profile to check again or cancel the upload.")
        } catch is CancellationError { } catch { errorMessage = error.localizedDescription }
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
            NLForm {
                NLFormSection("Password") {
                    NLSecureField(title: "Current password", text: $currentPassword)
                    NLSecureField(title: "New password", text: $newPassword)
                    NLSecureField(title: "Confirm new password", text: $confirmPassword)
                }

                if !successMessage.isEmpty {
                    NLFormSection {
                        Text(successMessage)
                            .foregroundColor(NLColor.navy)
                    }
                }
                if !errorMessage.isEmpty {
                    NLFormSection {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    }
                }

                NLFormSection {
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
            errorMessage = "Please enter your current password."
            return
        }
        if let validationMessage = PasswordValidation.message(for: newPassword) {
            errorMessage = validationMessage.replacingOccurrences(of: "Password must", with: "New password must")
            return
        }
        guard currentPassword != newPassword else {
            errorMessage = "New password must be different from your current password."
            return
        }
        guard newPassword == confirmPassword else {
            errorMessage = "New passwords do not match."
            return
        }

        isSaving = true
        defer { isSaving = false }
        do {
            try await APIService.shared.changePassword(currentPassword: currentPassword, newPassword: newPassword)
            currentPassword = ""
            newPassword = ""
            confirmPassword = ""
            successMessage = "Your password has been updated."
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
            NLForm {
                NLFormSection("Contact") {
                    NLTextField(title: "Name", text: $name)
                    NLTextField(title: "Email", text: $email, keyboardType: .emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    NLSelectField(title: "Topic", selection: $topic, value: topic) {
                        ForEach(topics, id: \.self) { topic in
                            Text(topic).tag(topic)
                        }
                    }
                }

                NLFormSection("Message") {
                    NLTextField(title: "Subject", text: $subject)
                    TextEditor(text: $message)
                        .frame(minHeight: 120)
                }

                if !successMessage.isEmpty {
                    NLFormSection {
                        Text(successMessage)
                            .foregroundColor(NLColor.navy)
                    }
                }
                if !errorMessage.isEmpty {
                    NLFormSection {
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

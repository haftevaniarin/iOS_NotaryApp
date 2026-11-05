import SwiftUI

struct CredentialsEditor: View {
    @StateObject private var model: CredentialsEditorModel

    init(model: CredentialsEditorModel? = nil) {
        _model = StateObject(wrappedValue: model ?? CredentialsEditorModel())
    }

    var body: some View {
        NLCard {
            VStack(alignment: .leading, spacing: NLSpacing.md) {
                Text("Credentials").font(NLTypography.cardTitle).foregroundColor(NLColor.navy)
                Text("Keep your commission, insurance, and background check up to date.")
                    .font(NLTypography.caption).foregroundColor(NLColor.muted)
                ErrorBanner(message: model.error)
                BannerView(kind: .success, message: model.success)
                if model.isLoading {
                    ProgressView("Loading credentials…")
                } else if let saved = model.saved {
                    if !CredentialSection.allCases.contains(where: { $0.isAdded(in: saved) }) {
                        Text("No credentials added yet.").font(NLTypography.body).foregroundColor(NLColor.muted)
                    }
                    ForEach(model.addedSections) { section in
                        summary(section, credentials: saved)
                    }
                    if CredentialSection.additional.isAdded(in: saved) {
                        summary(.additional, credentials: saved)
                    }
                    DisclosureGroup(isExpanded: $model.isExpanded) {
                        VStack(alignment: .leading, spacing: NLSpacing.lg) {
                            Text("Dates use YYYY-MM-DD. Clear all fields in a credential to remove it.")
                                .font(NLTypography.caption).foregroundColor(NLColor.muted)
                            ForEach(CredentialSection.summarySections) { section in
                                fields(section)
                            }
                            DisclosureGroup("Additional credential", isExpanded: $model.isAdditionalExpanded) {
                                fields(.additional).padding(.top, NLSpacing.md)
                            }
                            Button(model.isSaving ? "Saving…" : "Save Credentials") {
                                Task { await model.save() }
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(!model.canSave)
                            .accessibilityIdentifier("Save Credentials")
                        }.padding(.top, NLSpacing.md)
                    } label: {
                        Text("Edit credentials").font(NLTypography.bodyStrong)
                    }
                    .tint(NLColor.navy)
                } else {
                    Button("Retry loading credentials") { Task { await model.load() } }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
        }.task { await model.load() }
    }

    private func summary(_ section: CredentialSection, credentials: Credentials) -> some View {
        let expiration = credentials[keyPath: section.expirationKey]
        let status = CredentialDates.status(expiration)
        return VStack(alignment: .leading, spacing: NLSpacing.xs) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    summaryTitle(section, credentials: credentials)
                    Spacer(minLength: NLSpacing.sm)
                    expirationBadge(status)
                }
                VStack(alignment: .leading, spacing: NLSpacing.xs) {
                    summaryTitle(section, credentials: credentials)
                    expirationBadge(status)
                }
            }
            Text(expiration.map { "Expires \(CredentialDates.dayString($0))" } ?? "Expiration date not provided")
                .font(NLTypography.caption).foregroundColor(NLColor.muted)
                .accessibilityLabel(status.accessibleDescription + (expiration.map { ", \(CredentialDates.dayString($0))" } ?? ""))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(NLSpacing.md)
        .background(NLColor.parchment.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
    }

    private func summaryTitle(_ section: CredentialSection, credentials: Credentials) -> some View {
        Text(section == .additional ? credentials.certificationName ?? section.title : section.title)
            .font(NLTypography.bodyStrong).foregroundColor(NLColor.navy)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func expirationBadge(_ status: CredentialExpiration) -> some View {
        if let title = status.badgeTitle {
            Text(title).font(NLTypography.small)
                .foregroundColor(status == .expired ? NLColor.danger : NLColor.warning)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background((status == .expired ? NLColor.danger : NLColor.warning).opacity(0.1), in: Capsule())
        }
    }

    private func fields(_ section: CredentialSection) -> some View {
        VStack(alignment: .leading, spacing: NLSpacing.md) {
            Text(section.title).font(NLTypography.cardTitle).foregroundColor(NLColor.navy)
            ForEach(section.fields) { field in
                NLTextField(title: field.isDate ? "\(field.title) (YYYY-MM-DD)" : field.title,
                            text: Binding(get: { model.draft[keyPath: field.key] ?? "" },
                                          set: { model.edit(field, value: $0) }),
                            keyboardType: field.kind == .coverage ? .decimalPad : .default,
                            accessibilityName: "\(section.title) \(field.title.lowercased())")
                    .textInputAutocapitalization(field.id == "commissionState" ? .characters : .never)
                    .autocorrectionDisabled()
                    .disabled(!model.canEdit)
            }
        }
    }

    static func expirationStatus(_ value: String, today: Date = Date()) -> String {
        switch CredentialDates.status(value, today: today) {
        case .missing, .invalid: "Enter a valid expiration date."
        case .expired: "Expired"
        case .expiringSoon(let days): "Expires in \(days) days"
        case .current: "Current"
        }
    }
}

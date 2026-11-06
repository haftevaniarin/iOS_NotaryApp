import SwiftUI

struct LegalDocumentView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let kind: LegalDocumentKind
    var onSignIn: (() -> Void)? = nil
    @State private var showsSupportForm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenTitleBlock(title: kind.title, subtitle: kind.subtitle)
                Button(appState.currentUser == nil ? "Sign in" : "Back to dashboard") {
                    if appState.currentUser != nil {
                        appState.selectedSection = .dashboard
                    } else {
                        if let onSignIn { onSignIn() } else { appState.auth.navigate(.login) }
                    }
                    dismiss()
                }
                .buttonStyle(SecondaryButtonStyle())

                NLCard {
                    VStack(alignment: .leading, spacing: 12) {
                        paragraph(kind.intro, size: 14.5)
                        paragraph(LegalDocumentKind.templateNotice, size: 13)
                    }
                }

                NLCard(inset: 28) {
                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(kind.sections, id: \.title) { section in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(section.title)
                                    .font(NLFonts.serif(18))
                                    .foregroundStyle(NLColor.navy)
                                    .accessibilityAddTraits(.isHeader)
                                ForEach(section.paragraphs, id: \.self) { text in
                                    paragraph(text)
                                }
                            }
                        }
                    }
                }

                NLCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Contact")
                            .font(NLFonts.serif(16))
                            .foregroundStyle(NLColor.navy)
                            .accessibilityAddTraits(.isHeader)
                        paragraph(LegalDocumentKind.contactMessage)
                        if showsSupportForm {
                            LegalSupportContactForm(sourcePage: kind.rawValue)
                        } else {
                            Button { showsSupportForm = true } label: {
                                Label("Contact support", systemImage: "paperplane")
                            }
                            .buttonStyle(PrimaryButtonStyle())
                        }
                    }
                }
            }
            .nlScreenPadding()
        }
        .background(ParchmentBackground())
        .id(kind)
    }

    private func paragraph(_ text: String, size: CGFloat = 14) -> some View {
        Text(text)
            .font(NLFonts.sans(size))
            .foregroundStyle(NLColor.muted)
            .lineSpacing(size * 0.35)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }
}

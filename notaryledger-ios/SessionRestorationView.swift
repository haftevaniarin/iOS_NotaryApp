import SwiftUI

struct SessionRestorationView: View {
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: NLSpacing.xl) {
                    VStack(spacing: NLSpacing.sm) {
                        NLSeal(size: 64).accessibilityHidden(true)
                        Text("Notary Ledger")
                            .font(NLFonts.serif(23)).foregroundStyle(NLColor.navy)
                        Text("SIGNING AGENT DESK")
                            .font(NLTypography.small).tracking(0.69).foregroundStyle(NLColor.muted)
                    }.accessibilityElement(children: .combine)

                    NLCard(inset: 28) {
                        VStack(spacing: NLSpacing.md) {
                            ProgressView()
                                .controlSize(.large).tint(NLColor.navy)
                                .accessibilityHidden(true)
                            Text("Restoring your session")
                                .font(NLTypography.sectionTitle).foregroundStyle(NLColor.navy)
                                .accessibilityAddTraits(.isHeader)
                            Text("Checking your sign-in and preparing your workspace.")
                                .font(NLTypography.body).foregroundStyle(NLColor.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }.multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .accessibilityElement(children: .combine)
                    }

                    Text("Your workspace will open when your session is ready.")
                        .font(NLTypography.caption).foregroundStyle(NLColor.muted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: 380).padding(24)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
        }.background(ParchmentBackground())
            .accessibilityIdentifier("session-restoration")
    }
}

#Preview("Restoring session", traits: .fixedLayout(width: 390, height: 844)) {
    SessionRestorationView()
}

#Preview("Restoring session · Large text", traits: .fixedLayout(width: 375, height: 667)) {
    SessionRestorationView().dynamicTypeSize(.accessibility1)
}

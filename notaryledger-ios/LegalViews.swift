import SwiftUI

enum LegalDocumentKind {
    case terms
    case privacy

    var title: String {
        switch self {
        case .terms: "Terms & Conditions"
        case .privacy: "Privacy Policy"
        }
    }

    var sections: [(String, String)] {
        switch self {
        case .terms:
            [
                ("Use of Service", "Notary Ledger helps signing agents track orders, invoices, expenses, mileage, and tax summary records. You are responsible for reviewing entries and exports before using them for business or tax reporting."),
                ("Account Security", "Keep your login credentials secure and notify support if you believe your account has been accessed without permission."),
                ("Billing", "Paid plan access, checkout, account portal, past due, canceled, and inactive states are managed through the billing flow attached to your account."),
                ("Data", "Ledger data entered into the service remains available to your account subject to plan status, retention, export, and account deletion controls.")
            ]
        case .privacy:
            [
                ("Information Collected", "The app stores account details and ledger records such as signings, customers, invoices, expenses, mileage, support messages, and billing status where applicable."),
                ("How Data Is Used", "Data is used to provide ledger workflows, generate summaries and documents, maintain account security, support billing, and respond to support requests."),
                ("Data Controls", "Use Profile to request a data export, contact support, or request account deletion."),
                ("Billing Providers", "Payment workflows may be handled by Stripe checkout and account portal pages.")
            ]
        }
    }
}

struct LegalDocumentView: View {
    let kind: LegalDocumentKind

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NLSpacing.lg) {
                ScreenTitleBlock(title: kind.title, subtitle: "Notary Ledger account and ledger policy details.")

                ForEach(kind.sections, id: \.0) { section in
                    NLCard {
                        VStack(alignment: .leading, spacing: NLSpacing.sm) {
                            Text(section.0)
                                .font(.headline)
                                .foregroundColor(NLColor.navy)
                            Text(section.1)
                                .font(.subheadline)
                                .foregroundColor(NLColor.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(NLSpacing.lg)
        }
        .background(ParchmentBackground())
    }
}

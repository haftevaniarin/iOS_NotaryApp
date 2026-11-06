import Foundation

// Mirrors LEGAL_PAGES in the web app (src/App.jsx, revision 642cfc6).
// Keep the web wording, paragraph boundaries, and update date in sync.
enum LegalDocumentKind: String, CaseIterable {
    case terms
    case privacy

    static let lastUpdated = "July 19, 2026"
    static let supportEmail = "support@notaryledger.org"
    static let templateNotice = "This page is a general template for the app and should be reviewed by counsel before production use."
    static let contactMessage = "Send account, billing, privacy, or product support requests to support@notaryledger.org."

    var title: String { content.title }
    var subtitle: String { "\(content.subtitle) Last updated \(Self.lastUpdated)." }
    var intro: String { content.intro }
    var sections: [LegalSection] { content.sections }

    var content: LegalContent {
        switch self {
        case .terms:
            LegalContent(
                title: "Terms & Conditions",
                subtitle: "Rules for using Notary Ledger.",
                intro: "These Terms & Conditions describe the rules for accessing and using Notary Ledger. By creating an account or using the service, you agree to these terms.",
                sections: [
                    LegalSection(title: "1. Service Overview", paragraphs: [
                        "Notary Ledger provides tools for notary signing agents to track signings, customer records, expenses, mileage, estimated tax payments, and related bookkeeping notes.",
                        "The service is designed for recordkeeping support. It does not perform notarizations, verify signer identity, provide legal advice, or provide tax, accounting, or financial advice."
                    ]),
                    LegalSection(title: "2. Accounts and Security", paragraphs: [
                        "You are responsible for keeping your login credentials confidential and for all activity that occurs under your account.",
                        "You agree to provide accurate account information and to notify Notary Ledger at support@notaryledger.org if you believe your account has been accessed without permission."
                    ]),
                    LegalSection(title: "3. Your Records", paragraphs: [
                        "You retain responsibility for the accuracy, legality, and completeness of the signing, expense, mileage, customer, tax, and other records you enter into Notary Ledger.",
                        "You should keep independent backups of records required for business, legal, tax, audit, or compliance purposes."
                    ]),
                    LegalSection(title: "4. Tax and Compliance Disclaimer", paragraphs: [
                        "Reports, summaries, exports, and calculations in Notary Ledger are provided for convenience only and may not reflect every rule that applies to your business or location.",
                        "Review all records and reports with qualified legal, tax, accounting, or notarial compliance professionals before relying on them for filings, audits, or official decisions."
                    ]),
                    LegalSection(title: "5. Acceptable Use", paragraphs: [
                        "You agree not to misuse the service, attempt unauthorized access, interfere with service operation, upload malicious code, or use the service to store unlawful content.",
                        "You agree not to copy, resell, or exploit the service except as permitted by the app owner in writing."
                    ]),
                    LegalSection(title: "6. Third-Party Services", paragraphs: [
                        "Notary Ledger may rely on hosting, database, authentication, email, analytics, or other service providers to operate the app.",
                        "Those providers may process information as needed to deliver the service, subject to their own terms and privacy commitments."
                    ]),
                    LegalSection(title: "7. Availability and Changes", paragraphs: [
                        "The service may change, pause, or become unavailable from time to time for maintenance, updates, outages, or operational reasons.",
                        "Features may be added, changed, or removed. Continued use after posted updates means you accept the revised terms."
                    ]),
                    LegalSection(title: "8. Account Deletion", paragraphs: [
                        "You may request deletion through the account controls in the app where available. Deletion is intended to remove account data from the server and clear related local browser data after confirmation.",
                        "Some information may be retained if required for security, backup, legal, dispute, or compliance reasons."
                    ]),
                    LegalSection(title: "9. Limitation of Liability", paragraphs: [
                        "To the maximum extent allowed by law, Notary Ledger is provided as-is and without warranties of any kind.",
                        "The app owner is not responsible for lost profits, lost records, filing errors, compliance issues, indirect damages, or other losses arising from use of the service."
                    ])
                ]
            )
        case .privacy:
            LegalContent(
                title: "Privacy Policy",
                subtitle: "How Notary Ledger handles account and bookkeeping data.",
                intro: "This Privacy Policy explains what information Notary Ledger collects, how it is used, and the choices available to users.",
                sections: [
                    LegalSection(title: "1. Information We Collect", paragraphs: [
                        "Account information, such as name, email address, password authentication data, and profile details.",
                        "Business records you enter, such as signings, customer names, payer details, tax IDs, invoice numbers, fees, payment statuses, expenses, mileage logs, estimated tax payments, and report settings.",
                        "Technical information, such as browser type, device information, IP address, session data, error logs, and general usage information needed to operate and secure the service."
                    ]),
                    LegalSection(title: "2. How We Use Information", paragraphs: [
                        "To create accounts, authenticate users, provide app features, save records, generate reports, export files, and support account deletion.",
                        "To maintain, troubleshoot, secure, improve, and monitor the service.",
                        "To send service-related messages, including password reset emails and important account notices."
                    ]),
                    LegalSection(title: "3. Local Browser Storage", paragraphs: [
                        "Notary Ledger stores login session data in browser session storage. Some tax configuration, mileage logs, and estimated tax payment records may be stored in browser local storage.",
                        "Clearing browser data, changing browsers, or changing devices may remove locally stored records that are not also saved on the server."
                    ]),
                    LegalSection(title: "4. Sharing Information", paragraphs: [
                        "Information may be shared with service providers that help operate hosting, storage, authentication, email, security, analytics, or support functions.",
                        "Information may also be disclosed when required by law, to protect rights and safety, to investigate abuse, or in connection with a business transfer such as a merger or sale.",
                        "Notary Ledger does not sell your personal information in the ordinary meaning of selling data for money."
                    ]),
                    LegalSection(title: "5. Retention and Deletion", paragraphs: [
                        "Account and business records are retained while your account is active or as needed to provide the service.",
                        "When you delete your account, Notary Ledger attempts to remove server-side account data and clear related local browser data after the server confirms deletion.",
                        "Backup, security, legal, dispute, and compliance copies may be retained for a limited period where necessary."
                    ]),
                    LegalSection(title: "6. Security", paragraphs: [
                        "Notary Ledger uses administrative, technical, and organizational safeguards intended to protect user information.",
                        "No internet service can guarantee perfect security. You should use a strong password, keep credentials private, and sign out on shared devices."
                    ]),
                    LegalSection(title: "7. Your Choices", paragraphs: [
                        "You can review and update records inside the app, export certain reports, clear local browser data, and delete your account where the account deletion control is available.",
                        "For access, correction, deletion, or privacy questions that cannot be handled in the app, contact support@notaryledger.org."
                    ]),
                    LegalSection(title: "8. Children's Privacy", paragraphs: [
                        "Notary Ledger is intended for business users and is not directed to children under 13.",
                        "If you believe a child has provided personal information, contact support@notaryledger.org so it can be reviewed and removed where appropriate."
                    ]),
                    LegalSection(title: "9. Changes to This Policy", paragraphs: [
                        "This Privacy Policy may be updated from time to time. The latest version will be posted in the app with its effective date.",
                        "Continued use after an update means you acknowledge the revised policy."
                    ])
                ]
            )
        }
    }
}

struct LegalContent {
    let title: String
    let subtitle: String
    let intro: String
    let sections: [LegalSection]
}

struct LegalSection {
    let title: String
    let paragraphs: [String]
}

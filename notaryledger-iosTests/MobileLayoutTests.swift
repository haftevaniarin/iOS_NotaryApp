import SwiftUI
import UIKit
import XCTest
@testable import notaryledger_ios

#if DEBUG
@MainActor
final class MobileLayoutTests: XCTestCase {
    private var snapshotWindow: UIWindow?
    private var snapshotHost: UIHostingController<AnyView>?

    func testMobileScreensRenderWithBundledFontsAtPhoneWidths() async throws {
        for name in ["NLDisplay-SemiBold", "NLBody-Regular", "NLBody-SemiBold", "IBMPlexMono-Regular"] {
            XCTAssertNotNil(UIFont(name: name, size: 14), "Missing bundled font: \(name)")
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let host = UIHostingController(rootView: AnyView(Color.clear))
        host.safeAreaRegions = []
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        snapshotWindow = window
        snapshotHost = host
        defer {
            window.isHidden = true
            window.rootViewController = nil
            snapshotWindow = nil
            snapshotHost = nil
        }

        let previousService = APIService.shared
        let previousUser = SessionStorage.getCurrentUser()
        let previousToken = SessionStorage.getAccessToken()
        var card = BusinessCard()
        card.slug = "avery-notary"
        card.displayName = "Avery Notary"
        card.professionalTitle = "Notary Signing Agent"
        card.city = "Los Angeles"
        card.state = "CA"
        let cardBody = "{\"card\":\(String(decoding: try JSONEncoder().encode(card), as: UTF8.self))}"
        SessionStorage.saveAccessToken("layout-fixture-token")
        MockURLProtocol.requestHandler = { request in
            let path = request.url?.path ?? ""
            let body: String
            switch path {
            case "/api/config/maintenance": body = #"{"enabled":false}"#
            case "/api/auth/verify-email": body = "{}"
            case "/api/auth/me": body = #"{"success":true,"data":{"user":{"id":"layout-user","fullName":"Avery Notary","firstName":"Avery","lastName":"Notary","email":"avery@example.test","role":"ADMIN","defaultStartAddress":"123 Main Street","billing":{"plan":"PRO"}}}}"#
            case "/api/credentials": body = #"{"commissionNumber":"CA123456","commissionState":"CA","commissionExpirationDate":"2027-11-01","eoProvider":"Example Insurance","eoCoverageAmount":"100000"}"#
            case "/api/account/deletion-request": body = #"{"deletionRequest":null}"#
            case "/api/stripe/billing-status": body = #"{"billing":{"plan":"PRO","isPro":true,"subscriptionStatus":"ACTIVE","billingInterval":"monthly","features":{"invoiceGeneration":true}}}"#
            case "/api/business-card/me": body = cardBody
            case "/api/admin/audit-logs": body = #"{"items":[{"id":"a1","action":"USER_PROFILE_UPDATED","outcome":"SUCCESS","severity":"INFO","createdAt":"2026-11-02T12:00:00Z"}],"pagination":{"page":1,"pageSize":25,"total":1}}"#
            case "/api/estimated-tax-payments": body = #"[{"id":"p1","date":"2026-10-15","amount":125.50,"quarter":"Q4","taxYear":2026}]"#
            case "/api/reports/tax-summary": body = #"{"taxYear":2026,"totals":{"totalIncomeReceived":1250,"unpaidIncome":150,"totalNotarialActExemptFees":100,"businessExpenses":240,"totalTravelExpenses":30,"totalBusinessMiles":123,"netSelfEmploymentIncome":880,"seTaxableIncome":812.68,"estimatedSelfEmploymentTax":124.34,"estimatedTaxPayments":125.50}}"#
            case "/api/orders/layout-order/expenses": body = "[]"
            default:
                XCTFail("Unexpected snapshot request: \(path)")
                body = "{}"
            }
            return MockURLProtocol.jsonResponse(for: request, body: body)
        }
        let service = APIService(baseURL: "https://layout.example.test", session: MockURLProtocol.session())
        APIService.shared = service
        defer {
            APIService.shared = previousService
            MockURLProtocol.requestHandler = nil
            MockURLProtocol.requests = []
            if let previousUser { SessionStorage.saveCurrentUser(previousUser) } else { SessionStorage.clearCurrentUser() }
            if let previousToken { SessionStorage.saveAccessToken(previousToken) } else { SessionStorage.clearTokens() }
        }

        let state = AppState(api: service)
        state.currentUser = AuthUser(id: "layout-user", fullName: "Avery Notary", email: "avery@example.test", role: "ADMIN")
        let order = try JSONDecoder().decode(SigningOrder.self, from: Data(#"{"id":"layout-order","customerName":"Pacific Coast Signing Services","signerName":"Alexandra Sample","signingType":"Loan Signing","date":"2026-11-15","time":"14:30","fee":150.25,"notarialActFee":10,"paid":false,"invoiceNumber":"INV-2026-001","miles":24.5,"parkingFee":5}"#.utf8))
        state.orders = [order]
        state.expenses = [try JSONDecoder().decode(Expense.self, from: Data(#"{"id":"e1","date":"2026-11-01","description":"Printer paper and notary journal supplies","category":"Office supplies","amount":42.50,"businessUsePercent":100}"#.utf8))]

        let screens: [(String, AnyView)] = [
            ("Dashboard", AnyView(DashboardView())), ("Signings", AnyView(SigningsView())),
            ("Expenses", AnyView(ExpensesView())), ("Customers", AnyView(CustomersView())),
            ("Invoices", AnyView(InvoicesView())), ("Tax Summary", AnyView(TaxSummaryView())),
            ("Profile", AnyView(ProfileView())), ("Billing", AnyView(BillingView())),
            ("Digital Business Card", AnyView(BusinessCardView())),
            ("Rescission Calculator", AnyView(RescissionCalculatorView())),
            ("Admin Audit Logs", AnyView(AdminAuditLogsView())),
            ("Estimated Tax Payments", AnyView(EstimatedTaxPaymentsView(year: 2026, onChange: {}))),
            ("Signing Expenses", AnyView(OrderExpensesView(order: order))),
            ("Terms & Conditions", AnyView(LegalDocumentView(kind: .terms))),
            ("Privacy Policy", AnyView(LegalDocumentView(kind: .privacy))),
            ("Log In", AnyView(LoginView())),
            ("New Signing", AnyView(SigningOrderFormView(order: nil, onSave: { _ in }))),
            ("Log Expense", AnyView(ExpenseFormView(expense: nil, onSave: { _ in }))),
            ("Sign Up", AnyView(SignUpView())),
            ("Forgot Password", AnyView(ForgotPasswordView())),
            ("Reset Password", AnyView(ResetPasswordView(token: "layout-reset"))),
            ("Email Verification", AnyView(VerificationView(token: "layout-verify"))),
            ("Change Password", AnyView(ChangePasswordView())),
            ("Contact Support", AnyView(SupportContactView(sourcePage: "Profile"))),
            ("Signing Detail", AnyView(SigningOrderDetailView(order: order))),
            ("Import Signings", AnyView(ImportSigningsSheet())),
            ("Receipt Extraction", AnyView(ReceiptExtractionSheet())),
            ("Mileage Travel", AnyView(MileageTravelSheet(order: order, onSave: { _ in }))),
            ("Generate Invoice", AnyView(GenerateInvoiceSheet(order: order))),
            ("Review Spreadsheet", AnyView(SpreadsheetImportReviewView(draft: SpreadsheetDraft(filename: "signings.csv", mimeType: "text/csv", text: "Customer,Signer,Date,Fee\nAcme,Avery,2026-11-15,150"), onImport: { _ in }))),
            ("Navigation Menu", AnyView(LedgerSideMenu(selectedSection: .constant(.dashboard), isMenuOpen: .constant(true), primarySections: [.dashboard, .signings, .rescission, .invoices, .expenses, .customers, .taxSummary, .billing, .businessCard, .profile])))
        ]
        for width: CGFloat in [375, 402, 440] {
            for (title, screen) in screens {
                try await captureMobileScreen(screen, title: title, width: width, state: state)
            }
        }
        try await captureMobileScreen(AnyView(ProfileView()), title: "Profile Large Text", width: 375, state: state, dynamicTypeSize: .accessibility1)
    }

    private func captureMobileScreen(_ screen: AnyView, title: String, width: CGFloat, state: AppState, dynamicTypeSize: DynamicTypeSize = .large) async throws {
        let height: CGFloat = 812
        let root = VStack(spacing: 0) {
            if !["Log In", "Sign Up", "Forgot Password", "Reset Password"].contains(title) { LedgerTopBar(title: title, onMenu: {}) }
            NavigationStack { screen }
        }
        .frame(width: width, height: height)
        .environmentObject(state)
        .environment(\.nlViewportWidth, width)
        .environment(\.dynamicTypeSize, dynamicTypeSize)
        .font(NLTypography.body)
        .foregroundStyle(NLColor.ink)
        .background(NLColor.parchment)
        let host = try XCTUnwrap(snapshotHost)
        host.rootView = AnyView(root.id("\(title)-\(width)"))
        host.view.frame = CGRect(x: 0, y: 0, width: width, height: height)
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(120))
        host.view.layoutIfNeeded()
        XCTAssertEqual(SessionStorage.getAccessToken(), "layout-fixture-token", "The snapshot session must remain isolated from the live app.")
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { _ in
            host.view.drawHierarchy(in: CGRect(x: 0, y: 0, width: width, height: height), afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        let name = "ios-\(Int(width))-\(title)"
        attachment.name = name
        attachment.lifetime = .keepAlways
        XCTContext.runActivity(named: name) { $0.add(attachment) }
    }
}
#endif

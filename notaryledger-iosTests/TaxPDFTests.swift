import PDFKit
import XCTest
@testable import notaryledger_ios

@MainActor
final class TaxPDFTests: XCTestCase {
    private let user = AuthUser(id: "fixture-user", fullName: "Arin July", email: "arin@example.test", firstName: "Arin", lastName: "July")
    private func fixture(_ name: String) throws -> Data {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(forResource: "\(name)-report", withExtension: "json"))
        return try Data(contentsOf: url)
    }
    private func render(_ report: TaxPDFReport) throws -> Data {
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-05T10:30:00-08:00"))
        let zone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        return TaxPDFGenerator.document(user: user, report: report, generatedAt: date, timeZone: zone)
    }
    private func attach(_ data: Data, name: String) {
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "com.adobe.pdf")
        attachment.name = "ios-tax-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    func testFullSummaryAndEmptyReportsUseTheWebTaxTemplate() throws {
        for name in ["full", "summary", "empty"] {
            let report = try JSONDecoder().decode(TaxPDFReport.self, from: fixture(name))
            let data = try render(report)
            let pdf = try XCTUnwrap(PDFDocument(data: data))
            let text = try XCTUnwrap(pdf.string)
            XCTAssertGreaterThan(pdf.pageCount, 1)
            for expected in ["Notary Ledger", "Signing Agent Desk", "Arin July Tax Summary", "TAX YEAR", "GENERATED", "11/5/2026", "Taxpayer Information", "Email: arin@example.test", "Income Summary", "Expense Summary", "Mileage", "Business miles:", "Parking:", "Net Summary", "Notarial act fees exempt from SE tax", "Net self-employment income", "Estimate notice", "Estimated Tax Payments", "Estimated payments total", "CPA Note", "This is an estimate only, not a filing figure."] {
                XCTAssertTrue(text.contains(expected), "Missing \(expected) in \(name)")
            }
            for index in 0..<pdf.pageCount {
                let page = try XCTUnwrap(pdf.page(at: index))
                XCTAssertEqual(page.bounds(for: .mediaBox), CGRect(x: 0, y: 0, width: 612, height: 792))
                XCTAssertTrue(page.string?.contains("Page \(index + 1) of \(pdf.pageCount)") == true)
            }
            if name == "full" {
                for expected in ["CLIENT", "PAYER", "SIGNINGS", "TOTAL PAID", "1099", "Summit Title Co.", "CATEGORY", "DEDUCTIBLE", "Phone and internet", "Paid date warning", "QUARTER", "RUNNING TOTAL", "Q4", "$12,500.50", "$10,743.50", "$1,551.96", "$2,400.00"] {
                    XCTAssertTrue(text.contains(expected), "Missing \(expected)")
                }
            } else if name == "summary" {
                for expected in ["INCOME TYPE", "EXPENSE TYPE", "PAYMENT TYPE", "Order-specific expenses", "$3,400.50", "$2,965.50", "$500.00"] { XCTAssertTrue(text.contains(expected)) }
                XCTAssertFalse(text.contains("Paid signing count"))
            } else {
                for expected in ["No received income for this tax year.", "No expenses recorded for this tax year.", "No estimated tax payments recorded."] { XCTAssertTrue(text.contains(expected)) }
            }
            attach(data, name: name)
        }
    }
    func testReportPreservesBackendMoneyAndDetailInsteadOfRecalculatingTax() throws {
        let report = try JSONDecoder().decode(TaxPDFReport.self, from: fixture("full"))
        XCTAssertEqual(report.summary.incomeReceived, 12500.50)
        XCTAssertEqual(report.summary.estimatedSelfEmploymentTax, 1551.96)
        XCTAssertEqual(report.summary.netSelfEmploymentIncome, 10743.50)
        XCTAssertEqual(report.summary.selfEmploymentTaxableIncome, 10143.50)
        XCTAssertEqual(report.clients.count, 2)
        XCTAssertEqual(report.paidCount, 45)
        XCTAssertEqual(report.missingPaidDateCount, 1)
        XCTAssertEqual(report.categories.count, 2)
        XCTAssertEqual(report.payments.last?.runningTotal, 2400)
        XCTAssertEqual(TaxPDFGenerator.filename(user: user, report: report), "tax-summary-arin-july-2026.pdf")
    }
    func testDecimalStringsAndMissingOptionalDetailAreSupported() throws {
        let data = Data(#"{"taxYear":"2026","totals":{"totalIncomeReceived":"1234.56","businessExpenses":"45.67","orderExpenses":"10","totalTravelExpenses":"5","netSelfEmploymentIncome":"1173.89","estimatedTaxPayments":"40"},"incomeByClient":[{"clientName":"Client","orderCount":2,"totalIncomeReceived":"1234.56"}],"estimatedTaxPayments":[{"date":"2026-04-15","quarter":"Q1","amount":"10"},{"date":"2026-06-15","quarter":"Q2","amount":"30"}]}"#.utf8)
        let report = try JSONDecoder().decode(TaxPDFReport.self, from: data)
        XCTAssertEqual(report.clients.first?.paid, 1234.56)
        XCTAssertEqual(report.clients.first?.count, 2)
        XCTAssertEqual(report.totalDeductibleExpenses, 60.67, accuracy: 0.0001)
        XCTAssertEqual(report.payments.last?.runningTotal, 40)
        XCTAssertFalse(report.hasIncomeDetails)
        XCTAssertEqual(report.summary.netSelfEmploymentIncome, 1173.89)
    }
    func testLargeReportRetainsEveryRowRepeatsTableHeadingsAndCompletesAllSections() throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture("full")) as? [String: Any])
        object["incomeByClient"] = (1...100).map { ["clientName": "Client \($0)", "payerName": "Payer \($0)", "signingCount": 1, "totalPaid": 125] as [String: Any] }
        let report = try JSONDecoder().decode(TaxPDFReport.self, from: JSONSerialization.data(withJSONObject: object))
        let data = try render(report)
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        let text = try XCTUnwrap(pdf.string)
        XCTAssertGreaterThan(pdf.pageCount, 5)
        for index in 1...100 { XCTAssertTrue(text.contains("Client \(index)")) }
        XCTAssertTrue(text.contains("CPA Note"))
        for index in 0..<pdf.pageCount {
            let page = try XCTUnwrap(pdf.page(at: index))
            if page.string?.contains("Client ") == true { XCTAssertTrue(page.string?.contains("TOTAL PAID") == true) }
            XCTAssertTrue(page.string?.contains("Page \(index + 1) of \(pdf.pageCount)") == true)
        }
        attach(data, name: "multipage")
    }
    func testMalformedAmountsAndCountsAreRejected() throws {
        for json in [#"{"taxYear":2026,"totals":{"totalIncomeReceived":"not-money"}}"#,
                     #"{"taxYear":2026,"totals":{"totalIncomeReceived":"NaN"}}"#,
                     #"{"taxYear":2026,"totals":{"totalIncomeReceived":0},"incomeByClient":[{"orderCount":1e100}]}"#,
                     #"{"taxYear":2026.5,"totals":{"totalIncomeReceived":0}}"#] {
            XCTAssertThrowsError(try JSONDecoder().decode(TaxPDFReport.self, from: Data(json.utf8)))
        }
    }
}

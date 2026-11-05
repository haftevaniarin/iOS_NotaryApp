import PDFKit
import XCTest
@testable import notaryledger_ios

@MainActor
final class InvoicePDFTests: XCTestCase {
    private var user: AuthUser {
        AuthUser(id: "fixture-user", fullName: "Arin July", email: "arin@example.com", firstName: "Arin", lastName: "July")
    }
    private var issueDate: Date { DateParser.date(from: "2026-07-28")! }
    private var orders: [SigningOrder] {
        [SigningOrder(id: "order_1", customerName: "Summit Title Co.", payerName: "Summit Title Company", signerName: "Maya Thompson", signingType: "Loan Signing", date: "2026-07-18", fee: 175, paid: false, invoiceNumber: "AR-2026-1001", status: .pending),
         SigningOrder(id: "order_2", customerName: "Summit Title Co.", payerName: "Summit Title Company", signerName: "Noah Patel", signingType: "Refinance", date: "2026-07-20", fee: 200.50, paid: false, invoiceNumber: "AR-2026-1002", status: .overdue)]
    }

    func testSingleCustomerAndCustomInvoicesUseTheWebTemplate() throws {
        let single = try InvoiceDocument(user: user, customer: "Summit Title Co.", orders: [orders[0]], issuedAt: issueDate)
        let customer = try InvoiceDocument(user: user, customer: "Summit Title Co.", orders: orders, issuedAt: issueDate)
        let custom = try InvoiceDocument(user: user, customer: "Harbor Legal Docs", orders: [], customDescription: "General notary appointment for Sofia Ramirez", customAmount: 85.50, issuedAt: issueDate)
        for (name, invoice, amount, expectedSummary) in [
            ("single", single, "$175.00", "1 signing billed to Summit Title Co."),
            ("customer", customer, "$375.50", "2 signings billed to Summit Title Co."),
            ("custom", custom, "$85.50", "1 invoice item billed to Harbor Legal Docs")
        ] {
            let data = InvoicePDF.document(invoice)
            let document = try XCTUnwrap(PDFDocument(data: data))
            XCTAssertEqual(document.pageCount, 1)
            let page = try XCTUnwrap(document.page(at: 0))
            XCTAssertEqual(page.bounds(for: .mediaBox), CGRect(x: 0, y: 0, width: 612, height: 792))
            let text = try XCTUnwrap(document.string)
            for value in ["Notary Ledger", "Signing Agent Desk", "Invoice", "INVOICE #", "ISSUE DATE", "DUE DATE", "Jul 28, 2026", "Aug 27, 2026", "FROM", "BILL TO", "Arin July", "arin@example.com", "DATE", "SERVICE", "REF", "STATUS", "AMOUNT", expectedSummary, amount, "Subtotal", "Total", "Balance Due", "Payment note", "Thank you for your business.", "Page 1 of 1", "notaryledger.org"] {
                XCTAssertTrue(text.contains(value), "Missing \(value) from \(name) invoice")
            }
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "com.adobe.pdf")
            attachment.name = "ios-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        XCTAssertEqual(single.number, "AR-2026-1001")
        XCTAssertEqual(single.filename, "invoice-ar-2026-1001-summit-title-co.pdf")
        XCTAssertEqual(customer.number, "INV-20260728-summit-title-co")
        XCTAssertEqual(custom.filename, "invoice-inv-20260728-harbor-legal-docs-harbor-legal-docs.pdf")
    }

    func testPaginationRepeatsTableHeadersAndRetainsEverySigningAndTotal() throws {
        let manyOrders = (1...80).map { index in
            SigningOrder(id: "order-\(index)", customerName: "Summit Title Co.", signerName: "Signer \(index)", signingType: "Loan Signing", date: "2026-07-18", fee: 125.25, paid: false, invoiceNumber: "REF-\(index)", status: .pending)
        }
        let invoice = try InvoiceDocument(user: user, customer: "Summit Title Co.", orders: manyOrders, issuedAt: issueDate)
        let data = InvoicePDF.document(invoice)
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertGreaterThan(pdf.pageCount, 1)
        let text = try XCTUnwrap(pdf.string)
        for index in 1...80 { XCTAssertTrue(text.contains("REF-\(index)")) }
        XCTAssertTrue(text.contains("$10,020.00"))
        for index in 0..<pdf.pageCount {
            let page = try XCTUnwrap(pdf.page(at: index))
            let pageText = try XCTUnwrap(page.string)
            XCTAssertTrue(pageText.contains("Page \(index + 1) of \(pdf.pageCount)"))
            if pageText.contains("REF-") {
                for header in ["DATE", "SERVICE", "REF", "STATUS", "AMOUNT"] { XCTAssertTrue(pageText.contains(header)) }
            }
        }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "com.adobe.pdf")
        attachment.name = "ios-multipage"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testLongContentWrapsWithoutLosingDescriptionsOrFooter() throws {
        var longOrder = orders[0]
        longOrder.signingType = String(repeating: "A detailed notary service description with supporting documents. ", count: 180) + "END OF DESCRIPTION"
        longOrder.signerName = "Renée García"
        longOrder.invoiceNumber = "REFERENCE-WITH-A-LONG-NUMBER-2026-1001"
        let invoice = try InvoiceDocument(user: user, customer: "A customer with a long legal business name and an additional department", orders: [longOrder], issuedAt: issueDate)
        let pdf = try XCTUnwrap(PDFDocument(data: InvoicePDF.document(invoice)))
        XCTAssertGreaterThan(pdf.pageCount, 1)
        let text = try XCTUnwrap(pdf.string)
        XCTAssertTrue(text.contains("END OF DESCRIPTION"))
        XCTAssertTrue(text.contains("Renée García"))
        XCTAssertTrue(text.contains("Payment note"))
        XCTAssertTrue(text.contains("$175.00"))
        for index in 0..<pdf.pageCount {
            let page = try XCTUnwrap(pdf.page(at: index))
            XCTAssertTrue(page.string?.contains("Page \(index + 1) of \(pdf.pageCount)") == true)
        }
    }

    func testPaidCancelledAndEmptyOrdersCannotCreateIncorrectBalances() throws {
        var paid = orders[1]
        paid.paid = true
        var cancelled = orders[1]
        cancelled.status = .cancelled
        let invoice = try InvoiceDocument(user: user, customer: " Summit Title Co. ", orders: [orders[0], paid, cancelled], issuedAt: issueDate)
        XCTAssertEqual(invoice.items.count, 1)
        XCTAssertEqual(invoice.total, 175)
        XCTAssertEqual(invoice.payer, "Summit Title Company")
        XCTAssertThrowsError(try InvoiceDocument(user: user, customer: "Customer", orders: [paid, cancelled]))
        XCTAssertThrowsError(try InvoiceDocument(user: user, customer: "Customer", orders: [], customDescription: "Notary service", customAmount: .infinity))
        XCTAssertThrowsError(try InvoiceDocument(user: user, customer: "Customer", orders: [], customDescription: "Notary service", customAmount: -1))
        var samePayer = orders[0]
        samePayer.payerName = " summit title co. "
        let noDuplicatePayer = try InvoiceDocument(user: user, customer: samePayer.customerName, orders: [samePayer])
        XCTAssertNil(noDuplicatePayer.payer)
    }

    func testAllInvoiceExportEntryPointsWriteTheBrandedPDF() throws {
        let url = try LedgerPDF.invoice(user: user, customer: "Summit Title Co.", orders: orders)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let pdf = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertTrue(pdf.string?.contains("Signing Agent Desk") == true)
        XCTAssertTrue(pdf.string?.contains("Balance Due") == true)
        XCTAssertTrue(url.lastPathComponent.hasSuffix("-summit-title-co.pdf"))
    }
}

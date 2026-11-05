import UIKit
import CoreText

struct InvoiceDocument {
    struct Item {
        let date: String
        let service: String
        let reference: String
        let status: String
        let amount: Double
    }
    let number: String
    let issueDate: String
    let dueDate: String
    let fromName: String
    let fromEmail: String
    let customer: String
    let payer: String?
    let items: [Item]
    let summary: String
    var total: Double { items.reduce(0) { $0 + $1.amount } }
    var filename: String { "invoice-\(Self.filenamePart(number))-\(Self.filenamePart(customer)).pdf" }

    init(user: AuthUser?, customer: String, orders: [SigningOrder], customDescription: String? = nil,
         customAmount: Double? = nil, issuedAt: Date = Date()) throws {
        let orders = orders.filter(\.isUnpaidCandidate)
        let manual = customDescription != nil && customAmount != nil
        guard !orders.isEmpty || (manual && !Self.trim(customDescription).isEmpty) else {
            throw APIError.serverError("There are no unpaid signings to invoice.")
        }
        self.customer = Self.trim(customer).nilIfEmpty ?? Self.trim(orders.first?.customerName).nilIfEmpty ?? "Customer"
        issueDate = DateParser.apiDateString(from: issuedAt)
        dueDate = DateParser.apiDateString(from: Calendar.current.date(byAdding: .day, value: 30, to: issuedAt) ?? issuedAt)
        let reference = orders.count == 1 ? Self.trim(orders[0].invoiceNumber) : ""
        let suffix = orders.count == 1 ? String(Self.filenamePart(orders[0].id).suffix(8)) : String(Self.filenamePart(self.customer).prefix(18))
        number = reference.nilIfEmpty ?? "INV-\(issueDate.replacingOccurrences(of: "-", with: ""))-\(suffix)"
        let splitName = [Self.trim(user?.firstName), Self.trim(user?.lastName)].filter { !$0.isEmpty }.joined(separator: " ")
        fromName = splitName.nilIfEmpty ?? Self.trim(user?.fullName).nilIfEmpty ?? Self.trim(user?.email).nilIfEmpty ?? "Notary Ledger User"
        fromEmail = user?.email ?? ""
        let payerName = Self.trim(orders.first?.payerName)
        payer = payerName.count > 1 && payerName.lowercased() != self.customer.lowercased() ? payerName : nil
        if manual, let customDescription, let customAmount {
            items = [Item(date: "", service: Self.trim(customDescription), reference: "", status: "Pending", amount: customAmount)]
            summary = "1 invoice item billed to \(self.customer)"
        } else {
            items = orders.map { order in
                Item(date: Self.displayDate(order.date),
                     service: (order.signingType?.nilIfEmpty ?? "Notary signing") + (order.signerName.isEmpty ? "" : " for \(order.signerName)"),
                     reference: order.invoiceNumber, status: order.status?.rawValue ?? "Pending", amount: order.fee)
            }
            summary = "\(items.count) signing\(items.count == 1 ? "" : "s") billed to \(self.customer)"
        }
        guard items.allSatisfy({ $0.amount.isFinite && $0.amount >= 0 }), total.isFinite else {
            throw APIError.serverError("Enter a valid invoice amount.")
        }
    }

    static func trim(_ value: String?) -> String { value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
    static func filenamePart(_ value: String) -> String {
        trim(value).lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-")).nilIfEmpty ?? "user"
    }
    static func displayDate(_ value: String) -> String {
        guard let date = DateParser.date(from: value) else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
    static func currency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: amount)) ?? "$0.00"
    }
}

// Port of the web app's downloadInvoicePdf template (App.jsx). Coordinates are
// US Letter points; text uses PDF baseline positions and Helvetica/Times fonts.
// Plan pages first so every footer can include the final page count.
enum InvoicePDF {
    private typealias Layout = BrandedPDF.Layout
    private typealias Mark = BrandedPDF.Mark
    private static let ink = BrandedPDF.ink
    private static let parchment = BrandedPDF.parchment
    private static let brass = BrandedPDF.brass
    private static let slate = BrandedPDF.slate
    private static let border = BrandedPDF.border
    private static func font(_ size: CGFloat, bold: Bool = false, serif: Bool = false) -> UIFont {
        BrandedPDF.font(size, bold: bold, serif: serif)
    }
    static func document(_ invoice: InvoiceDocument) -> Data {
        let layout = Layout()
        layout.add(.stamp)
        layout.text("Notary Ledger", 86, 58, size: 13, bold: true, serif: true, width: 160)
        layout.text("Signing Agent Desk", 86, 72, size: 7.5, bold: true, color: slate, width: 160)
        // Grow metadata and billing blocks only when long values need extra room.
        let metadata = [("INVOICE #", invoice.number), ("ISSUE DATE", InvoiceDocument.displayDate(invoice.issueDate)), ("DUE DATE", InvoiceDocument.displayDate(invoice.dueDate))]
        let metadataHeights = metadata.map { max(21, CGFloat(Layout.wrapped($0.1, width: 92, font: font(9.5, bold: true)).count) * 10.925 + 7) }
        let metadataHeight = max(82, metadataHeights.reduce(0, +) + 19)
        layout.box(388, 46, 180, metadataHeight, radius: 8, stroke: border)
        var baseline: CGFloat = 64
        for (index, row) in metadata.enumerated() {
            layout.text(row.0, 402, baseline, size: 7.5, bold: true, color: slate, width: 58)
            layout.text(row.1, 554, baseline, size: 9.5, bold: true, width: 92, align: .right)
            baseline += metadataHeights[index]
        }
        // A two-line reference still fits above the web template's rule at 140.
        let headerExtra = max(0, metadataHeight - 90)
        layout.text("Invoice", 44, 122 + headerExtra, size: 26, bold: true, serif: true, width: 220)
        layout.line(44, 140 + headerExtra, 568, 140 + headerExtra, color: brass, width: 2)
        layout.y = 168 + headerExtra
        let billY = layout.y
        layout.text("FROM", 44, billY, size: 8, bold: true, color: slate, width: 250)
        layout.text("BILL TO", 318, billY, size: 8, bold: true, color: slate, width: 250)
        let fromNameLines = Layout.wrapped(invoice.fromName, width: 250, font: font(10.5, bold: true)).count
        let toNameLines = Layout.wrapped(invoice.customer, width: 250, font: font(10.5, bold: true)).count
        layout.text(invoice.fromName, 44, billY + 20, size: 10.5, bold: true, width: 250)
        layout.text(invoice.customer, 318, billY + 20, size: 10.5, bold: true, width: 250)
        let fromExtra = CGFloat(max(0, fromNameLines - 1)) * 12.075
        let toExtra = CGFloat(max(0, toNameLines - 1)) * 12.075
        let emailHeight = layout.text(invoice.fromEmail, 44, billY + 36 + fromExtra, size: 9.5, color: slate, width: 250)
        let payerHeight = invoice.payer.map { layout.text("Payer: \($0)", 318, billY + 36 + toExtra, size: 9.5, color: slate, width: 250) } ?? 0
        let billExtra = max(fromExtra + max(0, emailHeight - 13.925), toExtra + max(0, payerHeight - 13.925))
        layout.line(306, billY - 2, 306, billY + 54 + billExtra)
        layout.line(44, billY + 62 + billExtra, 568, billY + 62 + billExtra)
        layout.y += 84 + billExtra
        layout.y += layout.text(invoice.summary, 44, layout.y, color: slate) + 14
        layout.invoiceTableHeader()

        for (index, item) in invoice.items.enumerated() {
            let values = [item.date.nilIfEmpty ?? "-", item.service, item.reference.nilIfEmpty ?? "-", item.status, InvoiceDocument.currency(item.amount)]
            let widths: [CGFloat] = [70, 220, 78, 48, 70]
            let columns = zip(values, widths).enumerated().map { column, pair in
                Layout.wrapped(pair.0, width: pair.1, font: font(9, bold: column == 4))
            }
            let lineCount = columns.map(\.count).max() ?? 1
            var offset = 0
            // Ordinary rows stay together. Oversized descriptions continue onto
            // additional pages, with repeated column headings and no lost text.
            let rowHeight = max(26, CGFloat(lineCount) * 13 + 10)
            if rowHeight <= 654, layout.ensure(rowHeight) { layout.invoiceTableHeader() }
            while offset < lineCount {
                if layout.y + 26 > 736 { layout.nextPage(); layout.invoiceTableHeader() }
                let count = min(lineCount - offset, max(1, Int((736 - layout.y - 10) / 13)))
                let height = max(26, CGFloat(count) * 13 + 10)
                if index % 2 == 1 { layout.box(44, layout.y - 4, 524, height) }
                layout.line(44, layout.y + height - 5, 568, layout.y + height - 5, width: 0.7)
                for column in columns.indices {
                    let lines = Array(columns[column].dropFirst(offset).prefix(count))
                    layout.drawLines(lines, [52, 132, 374, 458, 560][column], layout.y + 10,
                                     font: font(9, bold: column == 4), color: column == 1 || column == 4 ? ink : slate,
                                     align: column == 4 ? .right : .left)
                }
                offset += count
                layout.y += height
                if offset < lineCount { layout.nextPage(); layout.invoiceTableHeader() }
            }
        }
        layout.y += 16
        layout.ensure(108)
        let total = InvoiceDocument.currency(invoice.total)
        layout.text("Subtotal", 378, layout.y, color: slate, width: 95)
        layout.text(total, 558, layout.y, width: 82, align: .right)
        layout.y += 20
        layout.text("Total", 378, layout.y, size: 11, bold: true, color: slate, width: 95)
        layout.text(total, 558, layout.y, size: 11, bold: true, width: 82, align: .right)
        layout.y += 14
        layout.box(368, layout.y, 200, 34, radius: 7, fill: ink)
        layout.text("Balance Due", 378, layout.y + 21, size: 11, bold: true, color: parchment, width: 95)
        layout.text(total, 558, layout.y + 21, size: 12, bold: true, color: parchment, width: 82, align: .right)
        layout.y += 58
        layout.ensure(66)
        layout.box(44, layout.y, 524, 58, radius: 7, stroke: border)
        layout.box(44, layout.y, 3, 58, fill: brass)
        layout.text("Payment note", 60, layout.y + 20, size: 11, bold: true, width: 492)
        layout.text("Thank you for your business. Please remit payment according to the terms arranged for this signing.", 60, layout.y + 38, size: 9.5, color: slate, width: 492)

        return BrandedPDF.document(layout.pages, includeDomain: true)
    }
}

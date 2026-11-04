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
    private static let ink = color(27, 42, 74)
    private static let parchment = color(250, 246, 236)
    private static let brass = color(184, 137, 91)
    private static let slate = color(91, 100, 114)
    private static let border = color(228, 221, 203)
    private static func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> UIColor {
        UIColor(red: r / 255, green: g / 255, blue: b / 255, alpha: 1)
    }
    private static func font(_ size: CGFloat, bold: Bool = false, serif: Bool = false) -> UIFont {
        UIFont(name: serif ? (bold ? "TimesNewRomanPS-BoldMT" : "TimesNewRomanPSMT") : (bold ? "Helvetica-Bold" : "Helvetica"), size: size) ?? UIFont.systemFont(ofSize: size)
    }
    private enum Mark {
        case text(String, CGPoint, UIFont, UIColor)
        case box(CGRect, CGFloat, UIColor, UIColor?)
        case line(CGPoint, CGPoint, UIColor, CGFloat)
        case stamp

        func draw(in context: CGContext) {
            context.saveGState()
            defer { context.restoreGState() }
            switch self {
            case let .text(text, origin, font, color):
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color]))
                context.translateBy(x: origin.x, y: origin.y)
                context.scaleBy(x: 1, y: -1)
                context.textMatrix = .identity
                context.textPosition = .zero
                CTLineDraw(line, context)
            case let .box(rect, radius, fill, stroke):
                let path = UIBezierPath(roundedRect: rect, cornerRadius: radius).cgPath
                context.addPath(path)
                context.setFillColor(fill.cgColor)
                if let stroke {
                    context.setStrokeColor(stroke.cgColor)
                    context.setLineWidth(1)
                    context.drawPath(using: .fillStroke)
                } else { context.fillPath() }
            case let .line(start, end, color, width):
                context.setStrokeColor(color.cgColor)
                context.setLineWidth(width)
                context.move(to: start); context.addLine(to: end); context.strokePath()
            case .stamp:
                context.setStrokeColor(brass.cgColor)
                context.setLineWidth(1.2)
                context.setLineDash(phase: 0, lengths: [2.2, 2.2])
                context.strokeEllipse(in: CGRect(x: 44, y: 46, width: 32, height: 32))
                context.setLineDash(phase: 0, lengths: [])
                context.setFillColor(ink.cgColor)
                context.fillEllipse(in: CGRect(x: 48, y: 50, width: 24, height: 24))
                let face = InvoicePDF.font(11, bold: true, serif: true)
                let width = ("NL" as NSString).size(withAttributes: [.font: face]).width
                Mark.text("NL", CGPoint(x: 60 - width / 2, y: 66), face, parchment).draw(in: context)
            }
        }
    }

    private final class Layout {
        var pages: [[Mark]] = [[]]
        var y: CGFloat = 52
        // This drawing plan needs no actor-bound cleanup. Match the other model
        // lifetime workaround for iOS 26.1 (swiftlang/swift#88036).
        nonisolated deinit {}
        func add(_ mark: Mark) { pages[pages.count - 1].append(mark) }
        func nextPage() { pages.append([]); y = 52 }
        @discardableResult func ensure(_ height: CGFloat) -> Bool {
            guard y + height > 736 else { return false }
            nextPage(); return true
        }
        func box(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, radius: CGFloat = 0, fill: UIColor = parchment, stroke: UIColor? = nil) {
            add(.box(CGRect(x: x, y: y, width: width, height: height), radius, fill, stroke))
        }
        func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat, color: UIColor = border, width: CGFloat = 1) {
            add(.line(CGPoint(x: x1, y: y1), CGPoint(x: x2, y: y2), color, width))
        }
        static func wrapped(_ text: String, width: CGFloat, font: UIFont) -> [String] {
            text.components(separatedBy: "\n").flatMap { paragraph -> [String] in
                guard !paragraph.isEmpty else { return [""] }
                let string = paragraph as NSString
                let typesetter = CTTypesetterCreateWithAttributedString(NSAttributedString(string: paragraph, attributes: [.font: font]))
                var result: [String] = []
                var offset = 0
                while offset < string.length {
                    let count = max(1, CTTypesetterSuggestLineBreak(typesetter, offset, Double(width)))
                    result.append(string.substring(with: NSRange(location: offset, length: count)).trimmingCharacters(in: .whitespaces))
                    offset += count
                }
                return result
            }
        }
        @discardableResult func text(_ value: String, _ x: CGFloat, _ baseline: CGFloat, size: CGFloat = 10, bold: Bool = false,
                                     serif: Bool = false, color: UIColor = ink, width: CGFloat = 524, align: NSTextAlignment = .left) -> CGFloat {
            let face = InvoicePDF.font(size, bold: bold, serif: serif)
            let lines = Self.wrapped(value, width: width, font: face)
            drawLines(lines, x, baseline, font: face, color: color, align: align)
            return CGFloat(lines.count) * (size * 1.15 + 3)
        }
        func drawLines(_ lines: [String], _ x: CGFloat, _ baseline: CGFloat, font: UIFont, color: UIColor, align: NSTextAlignment = .left) {
            for (index, text) in lines.enumerated() {
                let width = (text as NSString).size(withAttributes: [.font: font]).width
                let offset: CGFloat = align == .right ? width : align == .center ? width / 2 : 0
                add(.text(text, CGPoint(x: x - offset, y: baseline + CGFloat(index) * font.pointSize * 1.15), font, color))
            }
        }
        func tableHeader() {
            ensure(32)
            box(44, y, 524, 24, radius: 5, fill: ink)
            for (title, x, width) in [("DATE", 52.0, 70.0), ("SERVICE", 132, 230), ("REF", 374, 80), ("STATUS", 458, 62)] {
                text(title, x, y + 16, size: 8.5, bold: true, color: parchment, width: width)
            }
            text("AMOUNT", 560, y + 16, size: 8.5, bold: true, color: parchment, width: 70, align: .right)
            y += 30
        }
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
        layout.tableHeader()

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
            if rowHeight <= 654, layout.ensure(rowHeight) { layout.tableHeader() }
            while offset < lineCount {
                if layout.y + 26 > 736 { layout.nextPage(); layout.tableHeader() }
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
                if offset < lineCount { layout.nextPage(); layout.tableHeader() }
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

        return UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).pdfData { context in
            for (index, page) in layout.pages.enumerated() {
                context.beginPage()
                page.forEach { $0.draw(in: context.cgContext) }
                Mark.line(CGPoint(x: 44, y: 758), CGPoint(x: 568, y: 758), border, 0.7).draw(in: context.cgContext)
                let footer = "Page \(index + 1) of \(layout.pages.count) · Generated via Notary Ledger · notaryledger.org"
                let face = font(8)
                let width = (footer as NSString).size(withAttributes: [.font: face]).width
                Mark.text(footer, CGPoint(x: 306 - width / 2, y: 774), face, slate).draw(in: context.cgContext)
            }
        }
    }
}

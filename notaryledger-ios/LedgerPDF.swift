import UIKit
import SwiftUI

// Shared paginated native PDF rendering for local invoice and tax exports.
enum LedgerPDF {
    static func document(title: String, lines: [String]) -> Data {
        let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        return UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
            var y: CGFloat = 0
            func page() {
                context.beginPage()
                (title as NSString).draw(at: CGPoint(x: 40, y: 35), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 22), .foregroundColor: UIColor(NLColor.navy)])
                y = 80
            }
            page()
            let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 11), .foregroundColor: UIColor.darkGray]
            for line in lines {
                // Split long paragraphs so no content is clipped at a page boundary.
                let paragraphs = line.components(separatedBy: "\n")
                for paragraph in paragraphs {
                    let text = paragraph as NSString
                    let height = max(18, text.boundingRect(with: CGSize(width: 532, height: CGFloat.greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil).height + 8)
                    if y + height > 750 { page() }
                    text.draw(in: CGRect(x: 40, y: y, width: 532, height: height), withAttributes: attributes)
                    y += height
                }
            }
        }
    }
    static func save(data: Data, filename: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(filename)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }
    static func invoice(user: AuthUser?, customer: String, orders: [SigningOrder], customDescription: String? = nil, customAmount: Double? = nil) throws -> URL {
        let items = orders.filter(\.isUnpaidCandidate)
        guard !items.isEmpty || (customAmount != nil && customDescription?.isEmpty == false) else { throw APIError.serverError("There are no unpaid signings to invoice.") }
        let issueDate = DateParser.apiDateString(from: Date())
        let dueDate = DateParser.apiDateString(from: Calendar.current.date(byAdding: .day, value: 30, to: Date())!)
        let reference = items.count == 1 && !items[0].invoiceNumber.isEmpty ? items[0].invoiceNumber : "INV-\(issueDate.replacingOccurrences(of: "-", with: ""))-\(TaxPDFGenerator.sanitizedFilename(customer).prefix(18))"
        let total = customAmount ?? items.reduce(0) { $0 + $1.fee }
        var lines = ["Invoice: \(reference)", "Issued: \(issueDate)    Due: \(dueDate)", "Bill from: \(user?.fullName ?? "Notary Ledger User")", user?.email ?? "", "Bill to: \(customer)", "Payer: \(items.first?.payerDisplayName ?? customer)", ""]
        for item in items {
            lines += ["\(item.displayDate) | \(item.signingType ?? "Notary signing") for \(item.signerName)", "Reference: \(item.invoiceNumber) | \(item.normalizedStatus.rawValue) | \(item.fee.currencyString)"]
        }
        if let customDescription, let customAmount { lines += ["\(customDescription) | \(customAmount.currencyString)"] }
        lines += ["", "Subtotal: \(total.currencyString)", "Total: \(total.currencyString)", "Balance due: \(total.currencyString)"]
        return try save(data: document(title: "Invoice", lines: lines), filename: "invoice-\(TaxPDFGenerator.sanitizedFilename(reference)).pdf")
    }
}

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
        let invoice = try InvoiceDocument(user: user, customer: customer, orders: orders,
                                          customDescription: customDescription, customAmount: customAmount)
        return try save(data: InvoicePDF.document(invoice), filename: invoice.filename)
    }
}

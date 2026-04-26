import Foundation
import PDFKit
import UIKit

struct TaxPDFGenerator {
    struct Options {
        let userFullName: String
        let userEmail: String
        let year: Int
        let orders: [SigningOrder]
    }

    static func sanitizedFilename(_ name: String) -> String {
        var s = name.lowercased()
        s = s.replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return s
    }

    static func generatePDF(options: Options) -> Data {
        // We'll create a single page for simplicity; for many orders pagination would be needed.
        let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792) // Letter size

        // Create attributed string content
        let title = NSAttributedString(string: "Tax Summary \(options.year)", attributes: [.font: UIFont.boldSystemFont(ofSize: 24)])

        let taxpayer = NSAttributedString(string: "Taxpayer: \(options.userFullName) (<\(options.userEmail)>)\n\n", attributes: [.font: UIFont.systemFont(ofSize: 12)])

        var bodyText = "Totals\n"
        let paidOrders = options.orders.filter { $0.paid }
        let grossIncome = paidOrders.reduce(0) { $0 + $1.fee }
        bodyText += "Paid count: \(paidOrders.count)\n"
        bodyText += String(format: "Gross income: $%.2f\n\n", grossIncome)

        bodyText += "Per-customer summary:\n"
        let groups = Dictionary(grouping: paidOrders) { $0.customerName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        for (key, orders) in groups {
            let name = orders.first?.customerName ?? key
            let total = orders.reduce(0) { $0 + $1.fee }
            bodyText += "- \(name): \(orders.count) orders, $" + String(format: "%.2f", total) + "\n"
        }

        bodyText += "\nPaid order details:\n"
        for order in paidOrders {
            bodyText += "\(order.displayDate) | \(order.customerName) | \(order.signerName) | \(order.invoiceNumber) | $" + String(format: "%.2f", order.fee) + "\n"
        }

        bodyText += "\nCPA: This is a developer-generated summary."

        // Use NSMutableData for the PDF context
        let mutableData = NSMutableData()
        UIGraphicsBeginPDFContextToData(mutableData, pageBounds, nil)
        UIGraphicsBeginPDFPageWithInfo(pageBounds, nil)

        let titleRect = CGRect(x: 40, y: 40, width: pageBounds.width - 80, height: 30)
        title.draw(in: titleRect)
        let taxpayerRect = CGRect(x: 40, y: 80, width: pageBounds.width - 80, height: 40)
        taxpayer.draw(in: taxpayerRect)
        let bodyRect = CGRect(x: 40, y: 120, width: pageBounds.width - 80, height: pageBounds.height - 160)
        let bodyAttr = NSAttributedString(string: bodyText, attributes: [.font: UIFont.systemFont(ofSize: 10)])
        bodyAttr.draw(in: bodyRect)

        UIGraphicsEndPDFContext()

        return mutableData as Data
    }
}

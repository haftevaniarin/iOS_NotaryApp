import Foundation

#if canImport(Testing)
import Testing
@testable import notaryledger_ios

struct OrderParsingTests {
    @Test func decodesBackendOrderShapeAndNormalizesCancelledStatus() throws {
        let json = """
        {
          "_id": "abc123",
          "customerName": "Acme Title",
          "payerName": "Acme Payables",
          "signerName": "Jamie Smith",
          "signingType": "Refinance",
          "date": "2026-09-15",
          "time": "10:30 AM",
          "fee": "150.50",
          "notarialActFee": "15",
          "paid": true,
          "paidDate": "2026-09-16",
          "invoiceNumber": "INV-100",
          "paymentStatus": "canceled",
          "miles": "12.5",
          "travelFee": "20"
        }
        """.data(using: .utf8)!

        let order = try JSONDecoder().decode(SigningOrder.self, from: json)

        #expect(order.id == "abc123")
        #expect(order.fee == 150.50)
        #expect(order.notarialActFee == 15)
        #expect(order.mileage == 12.5)
        #expect(order.normalizedStatus == .cancelled)
        #expect(order.countsInFinancialTotals == false)
        #expect(order.isUnpaidCandidate == false)
    }

    @Test func cancelledPayloadForcesUnpaidAndNullPaidDate() throws {
        let payload = SigningOrderPayload(
            customerName: "Acme Title",
            payerName: "Acme Payables",
            signerName: "Jamie Smith",
            signingType: "Refinance",
            date: "2026-09-15",
            time: "10:30",
            fee: 150,
            notarialActFee: 15,
            paid: true,
            paidDate: "2026-09-16",
            invoiceNumber: "INV-100",
            notes: "Cancelled by signer",
            mileage: 12,
            travelFee: 20,
            status: .cancelled
        )

        let data = try APIService(baseURL: "https://api.example.test").encodedBody(payload)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(object?["paid"] as? Bool == false)
        #expect(object?["paidDate"] is NSNull)
        #expect(object?["status"] as? String == "Cancelled")
    }

    @Test func dashboardTotalsExcludeCancelledOrders() throws {
        let now = try #require(DateParser.date(from: "2026-09-20"))
        let orders = [
            SigningOrder(id: "paid", customerName: "A", signerName: "One", date: "2026-09-05", fee: 100, notarialActFee: 10, paid: true, status: .paid),
            SigningOrder(id: "unpaid", customerName: "B", signerName: "Two", date: "2026-09-12", fee: 200, notarialActFee: 20, paid: false, status: .pending),
            SigningOrder(id: "cancelled", customerName: "C", signerName: "Three", date: "2026-09-15", fee: 999, notarialActFee: 99, paid: false, status: .cancelled)
        ]

        let metrics = FinancialSummary.dashboardMetrics(orders: orders, now: now)

        #expect(metrics.monthRevenue == 100)
        #expect(metrics.pendingPayment == 200)
        #expect(metrics.ytdSigningOrderCount == 3)
        #expect(metrics.averageFeePerSigning == 150)
    }

    @Test func customerSummariesExcludeCancelledFromUnpaidAndInvoiceCandidates() {
        let orders = [
            SigningOrder(id: "1", customerName: "Acme", signerName: "One", date: "2026-09-05", fee: 100, paid: false, status: .pending),
            SigningOrder(id: "2", customerName: "Acme", signerName: "Two", date: "2026-09-06", fee: 100, paid: false, status: .cancelled)
        ]

        let summary = CustomerSummaries.build(from: orders).first

        #expect(summary?.unpaidCount == 1)
        #expect(summary?.invoiceCandidates.map(\.id) == ["1"])
        #expect(summary?.signingCount == 2)
    }
}
#endif

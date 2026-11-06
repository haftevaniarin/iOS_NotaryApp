import Foundation

// Preserve the complete tax report for export. The screen's compact TaxSummary
// intentionally has fewer fields and cannot supply the PDF's detail tables.
struct TaxPDFReport: Decodable {
    struct Client: Decodable {
        let name: String
        let payer: String
        let count: Int
        let paid: Double
        init(from decoder: Decoder) throws {
            let f = try TaxReportFields(decoder)
            name = try f.string(["clientName", "customerName", "name"], fallback: "Unknown client")
            payer = try f.string(["payerName", "payorName"], fallback: name)
            count = try f.count(["signingCount", "orderCount", "count"])
            paid = try f.number(["totalPaid", "totalIncomeReceived", "paidTotal", "amount", "total"]) ?? 0
        }
    }
    struct Category: Decodable {
        let name: String
        let count: Int
        let raw: Double
        let deductible: Double
        init(from decoder: Decoder) throws {
            let f = try TaxReportFields(decoder)
            name = try f.string(["category", "categoryName", "name"], fallback: "Other")
            count = try f.count(["count", "itemCount", "expenseCount"])
            raw = try f.number(["rawTotal", "totalAmount", "amount", "total"]) ?? 0
            deductible = try f.number(["deductibleTotal", "deductibleAmount", "businessAmount", "amount", "total"]) ?? 0
        }
    }
    struct Payment: Decodable {
        let date: String
        let quarter: String
        let amount: Double
        var runningTotal: Double
        init(from decoder: Decoder) throws {
            let f = try TaxReportFields(decoder)
            date = try f.string(["date"])
            quarter = try f.string(["quarter", "taxQuarter", "period"])
            amount = try f.number(["amount", "paymentAmount", "total"]) ?? 0
            runningTotal = try f.number(["runningTotal", "running_total"]) ?? 0
        }
    }
    private struct Order: Decodable {
        let paidDate: String
        let customer: String
        let payer: String
        let fee: Double
        let cancelled: Bool
        init(from decoder: Decoder) throws {
            let f = try TaxReportFields(decoder)
            paidDate = try f.string(["paidDate"])
            customer = try f.string(["customerName"], fallback: "Unknown client")
            payer = try f.string(["payerName"], fallback: customer)
            fee = try f.number(["fee"]) ?? 0
            let status = try f.string(["paymentStatus", "status"]).lowercased()
            cancelled = status == "cancelled" || status == "canceled"
        }
    }

    let summary: TaxSummary
    let clients: [Client]
    let categories: [Category]
    let payments: [Payment]
    let paidCount: Int
    let hasIncomeDetails: Bool
    let missingPaidDateCount: Int
    let rawExpenses: Double
    let deductibleExpenses: Double
    let orderExpenses: Double
    let totalDeductibleExpenses: Double
    let parking: Double
    let taxRate: Double

    init(from decoder: Decoder) throws {
        let root = try TaxReportFields(decoder)
        let totals = try root.object("totals")
        guard let income = try totals.number(["totalIncomeReceived", "signingFeeIncome"]),
              let yearNumber = try root.number(["taxYear", "year"]), let year = Int(exactly: yearNumber),
              (1900...9999).contains(year) else { throw APIError.invalidResponse }
        let business = try totals.number(["businessExpenses"]) ?? 0
        orderExpenses = try totals.number(["orderExpenses"]) ?? 0
        let combined = business + orderExpenses
        let travel = try totals.number(["totalTravelExpenses", "travelExpenses"]) ?? 0
        rawExpenses = try totals.number(["rawExpenseTotal"]) ?? combined
        deductibleExpenses = try totals.number(["deductibleExpenseTotal"]) ?? combined
        totalDeductibleExpenses = try totals.number(["totalDeductibleExpenses"]) ?? deductibleExpenses + travel
        parking = try totals.number(["parkingTotal"]) ?? 0
        taxRate = try totals.number(["selfEmploymentTaxRate", "taxRate"]) ?? 0
        // Keep the backend's financial figures; exporting must not recalculate tax.
        summary = TaxSummary(taxYear: year, incomeReceived: income,
                             unpaidIncome: try totals.number(["unpaidIncome"]) ?? 0,
                             businessExpenses: business, travelExpenses: travel,
                             notarialActFeeExemptPortion: try totals.number(["totalNotarialActExemptFees"]) ?? 0,
                             netSelfEmploymentIncome: try totals.number(["netSelfEmploymentIncome"]) ?? 0,
                             selfEmploymentTaxableIncome: try totals.number(["seTaxableIncome"]) ?? 0,
                             estimatedSelfEmploymentTax: try totals.number(["estimatedSelfEmploymentTax"]) ?? 0,
                             estimatedTaxPayments: try totals.number(["estimatedPaymentsTotal", "estimatedTaxPayments"]) ?? 0,
                             totalBusinessMiles: try totals.number(["totalBusinessMiles"]) ?? 0)
        let paid = try root.array(Order.self, ["paidOrders"]).filter { !$0.cancelled }
        let unpaid = try root.array(Order.self, ["unpaidOrders"]).filter { !$0.cancelled }
        paidCount = paid.count
        hasIncomeDetails = !paid.isEmpty || !unpaid.isEmpty
        let explicitMissing = try root.array(Order.self, ["missingPaidDateOrders"])
        missingPaidDateCount = explicitMissing.isEmpty ? paid.filter { $0.paidDate.isEmpty }.count : explicitMissing.count
        let clientRows = try root.array(Client.self, ["incomeByClient"])
        if clientRows.isEmpty, !paid.isEmpty {
            clients = Dictionary(grouping: paid, by: \.customer).map { name, rows in
                Client(name: name, payer: rows.first?.payer ?? name, count: rows.count, paid: rows.reduce(0) { $0 + $1.fee })
            }.sorted { $0.paid == $1.paid ? $0.name < $1.name : $0.paid > $1.paid }
        } else { clients = clientRows }
        categories = try root.array(Category.self, ["expensesByCategory"])
        var running: Double = 0
        payments = try root.array(Payment.self, ["estimatedPaymentsWithTotals", "estimatedTaxPayments", "payments"]).map {
            var payment = $0
            running += payment.amount
            if payment.runningTotal == 0 { payment.runningTotal = running }
            return payment
        }
        guard totalDeductibleExpenses.isFinite, rawExpenses.isFinite, deductibleExpenses.isFinite,
              payments.allSatisfy({ $0.runningTotal.isFinite }) else { throw APIError.invalidResponse }
    }
}

private extension TaxPDFReport.Client {
    init(name: String, payer: String, count: Int, paid: Double) {
        self.name = name; self.payer = payer; self.count = count; self.paid = paid
    }
}

private struct TaxReportKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil
    init(_ value: String) { stringValue = value }
    init?(stringValue: String) { self.init(stringValue) }
    init?(intValue: Int) { return nil }
}
private struct TaxReportFields {
    let values: KeyedDecodingContainer<TaxReportKey>
    init(_ decoder: Decoder) throws { values = try decoder.container(keyedBy: TaxReportKey.self) }
    func object(_ name: String) throws -> Self { try Self(values.superDecoder(forKey: TaxReportKey(name))) }
    func number(_ names: [String]) throws -> Double? {
        for name in names {
            let key = TaxReportKey(name)
            guard values.contains(key), try !values.decodeNil(forKey: key) else { continue }
            let number = (try? values.decode(Double.self, forKey: key)) ?? (try? values.decode(String.self, forKey: key)).flatMap(Double.init)
            guard let number, number.isFinite else {
                throw DecodingError.dataCorruptedError(forKey: key, in: values, debugDescription: "Expected a finite report number.")
            }
            return number
        }
        return nil
    }
    func string(_ names: [String], fallback: String = "") throws -> String {
        for name in names {
            if let value = try values.decodeIfPresent(String.self, forKey: TaxReportKey(name)), !value.isEmpty { return value }
        }
        return fallback
    }
    func count(_ names: [String]) throws -> Int {
        guard let count = Int(exactly: try number(names) ?? 0), count >= 0 else { throw APIError.invalidResponse }
        return count
    }
    func array<T: Decodable>(_ type: T.Type, _ names: [String]) throws -> [T] {
        for name in names {
            if let value = try values.decodeIfPresent([T].self, forKey: TaxReportKey(name)) { return value }
        }
        return []
    }
}

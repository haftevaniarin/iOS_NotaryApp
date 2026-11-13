import Foundation

struct ReportField: Identifiable {
    enum Format { case text, money, number, miles, percent, date }
    let key: String
    let title: String
    var format: Format = .money
    var id: String { key }
    init(_ key: String, _ title: String, _ format: Format = .money) {
        self.key = key; self.title = title; self.format = format
    }
    func formatted(in row: ReportValue) -> String? {
        let value = row[key]
        switch format {
        case .text: return value.text
        case .date:
            // Appointment and expense dates are calendar days, not local instants.
            guard let text = value.text else { return nil }
            return DateParser.date(from: String(text.prefix(10))).map { Formatters.displayDate.string(from: $0) } ?? text
        case .money: return value.decimal?.formatted(.currency(code: "USD"))
        case .number: return value.decimal?.formatted(.number.precision(.fractionLength(0...2)))
        case .miles: return value.decimal.map { $0.formatted(.number.precision(.fractionLength(0...2))) + " mi" }
        case .percent: return value.decimal.map { $0.formatted(.number.precision(.fractionLength(0...2))) + "%" }
        }
    }
}

struct ReportSection: Identifiable {
    let path: String
    let title: String
    let fields: [ReportField]
    var id: String { path }
    init(_ path: String, _ title: String, _ fields: [ReportField]) {
        self.path = path; self.title = title; self.fields = fields
    }
}

extension LedgerReportKind {
    var metrics: [ReportField] {
        switch self {
        case .overview:
            [.init("grossRevenue", "Gross Revenue"), .init("collectedRevenue", "Collected"),
             .init("outstandingRevenue", "Outstanding"), .init("totalExpenses", "Expenses"),
             .init("netProfit", "Net Profit"), .init("totalOrders", "Total Orders", .number),
             .init("completedOrders", "Completed Orders", .number), .init("cancelledOrders", "Cancelled Orders", .number),
             .init("totalMileage", "Business Miles", .miles), .init("averageSigningFee", "Average Signing Fee")]
        case .income:
            [.init("grossRevenue", "Gross Revenue"), .init("collectedRevenue", "Collected"),
             .init("outstandingRevenue", "Outstanding"), .init("averageSigningFee", "Average Signing Fee"),
             .init("totalRevenueGeneratingOrders", "Revenue-generating Orders", .number)]
        case .profitLoss:
            [.init("grossRevenue", "Gross Revenue"), .init("totalExpenses", "Expenses"),
             .init("netProfit", "Net Profit"), .init("profitMargin", "Profit Margin", .percent)]
        case .outstanding:
            [.init("totalOutstanding", "Outstanding"), .init("outstandingOrderCount", "Outstanding Orders", .number)]
        case .mileage:
            [.init("totalBusinessMiles", "Business Miles", .miles), .init("totalTrips", "Trips", .number),
             .init("ordersWithMileage", "Orders with Mileage", .number), .init("averageMilesPerOrder", "Average Miles per Order", .miles),
             .init("estimatedMileageDeduction", "Estimated Mileage Deduction"), .init("mileageRate", "Mileage Rate")]
        case .expenses:
            [.init("totalExpenses", "Expenses"), .init("expenseCount", "Expense Count", .number), .init("averageExpense", "Average Expense")]
        case .clients: []
        }
    }

    var chartFields: [ReportField] {
        switch self {
        case .overview, .profitLoss: [.init("revenue", "Revenue"), .init("profit", "Profit")]
        case .income: [.init("grossRevenue", "Revenue"), .init("paidRevenue", "Collected"), .init("unpaidRevenue", "Outstanding")]
        case .mileage: [.init("businessMiles", "Business Miles", .miles)]
        case .expenses: [.init("amount", "Expenses")]
        default: []
        }
    }
    var chartPath: String { self == .mileage || self == .expenses ? "byMonth" : "trend" }

    var sections: [ReportSection] {
        let period = ReportField("period", "Period", .text)
        let clientFields: [ReportField] = [
            .init("clientName", "Client", .text), .init("totalOrders", "Orders", .number),
            .init("completedOrders", "Completed Orders", .number), .init("grossRevenue", "Revenue"),
            .init("collectedRevenue", "Collected"), .init("outstandingRevenue", "Outstanding"),
            .init("averageSigningFee", "Average Signing Fee"), .init("totalMileage", "Mileage", .miles),
            .init("averageMilesPerOrder", "Average Miles per Order", .miles), .init("averagePaymentDays", "Average Payment Days", .number)]
        switch self {
        case .overview:
            return [.init("trend", "Monthly Performance", [period, .init("revenue", "Revenue"), .init("collected", "Collected"),
                .init("expenses", "Expenses"), .init("profit", "Profit"), .init("orders", "Orders", .number), .init("mileage", "Mileage", .miles)])]
        case .income:
            return [.init("trend", "Income by Month", [period, .init("grossRevenue", "Revenue"), .init("paidRevenue", "Collected"),
                .init("unpaidRevenue", "Outstanding"), .init("orderCount", "Orders", .number), .init("averageFee", "Average Fee")])]
        case .profitLoss:
            return [.init("trend", "Profit & Loss by Month", [period, .init("revenue", "Revenue"), .init("expenses", "Expenses"), .init("profit", "Profit")])]
        case .outstanding:
            return [.init("agingBuckets", "Payment Aging", [.init("bucket", "Days Outstanding", .text), .init("count", "Orders", .number), .init("totalOutstanding", "Outstanding")]),
                .init("items", "Outstanding Orders", [
                    .init("clientName", "Client", .text), .init("signerName", "Signer", .text), .init("appointmentDate", "Appointment Date", .date),
                    .init("invoiceNumber", "Invoice", .text), .init("originalAmount", "Original Amount"), .init("amountPaid", "Paid"),
                    .init("amountDue", "Amount Due"), .init("daysOutstanding", "Days Outstanding", .number), .init("paymentStatus", "Status", .text)])]
        case .mileage:
            return [.init("byMonth", "Mileage by Month", [period, .init("businessMiles", "Business Miles", .miles),
                .init("orderMiles", "Order Miles", .miles), .init("loggedMiles", "Logged Miles", .miles), .init("trips", "Trips", .number)]),
                .init("records.orderMileage", "Order Mileage", [.init("appointmentDate", "Date", .date), .init("clientName", "Client", .text),
                    .init("signerName", "Signer", .text), .init("invoiceNumber", "Invoice", .text), .init("miles", "Business Miles", .miles)]),
                .init("records.mileageLogs", "Mileage Logs", [.init("date", "Date", .date), .init("description", "Description", .text),
                    .init("startLocation", "From", .text), .init("endLocation", "To", .text), .init("miles", "Business Miles", .miles), .init("purpose", "Purpose", .text)])]
        case .expenses:
            return [.init("byCategory", "Expenses by Category", [.init("category", "Category", .text), .init("amount", "Amount"),
                .init("count", "Count", .number), .init("percentage", "Share", .percent)]),
                .init("byMonth", "Expenses by Month", [period, .init("amount", "Amount"), .init("count", "Count", .number)]),
                .init("expenses", "Expense Details", [.init("date", "Date", .date), .init("description", "Description", .text), .init("category", "Category", .text),
                    .init("originalAmount", "Original Amount"), .init("amount", "Business Amount"), .init("businessUsePercent", "Business Use", .percent), .init("notes", "Notes", .text)])]
        case .clients:
            return [.init("clients", "Client Performance", clientFields),
                    .init("rankings.highestRevenueClients", "Highest Revenue Clients", clientFields),
                    .init("rankings.highestOrderVolumeClients", "Highest Order Volume", clientFields),
                    .init("rankings.largestOutstandingBalanceClients", "Largest Outstanding Balances", clientFields)]
        }
    }
}

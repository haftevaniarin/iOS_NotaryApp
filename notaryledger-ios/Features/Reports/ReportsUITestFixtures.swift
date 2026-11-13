#if DEBUG
import Foundation

// Used only by AuthUITestFixtures; these values never replace live report data.
enum ReportsUITestFixtures {
    static func response(for path: String) -> String? {
        switch path {
        case "/api/reports/overview":
            #"{"totals":{"grossRevenue":350.35,"collectedRevenue":100.1,"outstandingRevenue":250.25,"totalExpenses":25.75,"netProfit":324.6,"totalOrders":4,"completedOrders":3,"cancelledOrders":1,"totalMileage":15.5,"averageSigningFee":116.78},"trend":[{"period":"2026-11","revenue":350.35,"collected":100.1,"expenses":25.75,"profit":324.6,"orders":3,"mileage":15.5}]}"#
        case "/api/reports/income":
            #"{"totals":{"grossRevenue":350.35,"collectedRevenue":100.1,"outstandingRevenue":250.25,"averageSigningFee":116.78,"totalRevenueGeneratingOrders":3},"trend":[{"period":"2026-11","grossRevenue":350.35,"paidRevenue":100.1,"unpaidRevenue":250.25,"orderCount":3,"averageFee":116.78}]}"#
        case "/api/reports/profit-loss":
            #"{"totals":{"grossRevenue":350.35,"totalExpenses":25.75,"netProfit":324.6,"profitMargin":92.65},"trend":[{"period":"2026-11","revenue":350.35,"expenses":25.75,"profit":324.6}]}"#
        case "/api/reports/outstanding-payments":
            #"{"totals":{"totalOutstanding":250.25,"outstandingOrderCount":2},"agingBuckets":[{"bucket":"0-30","count":2,"totalOutstanding":250.25}],"items":[{"orderId":"harbor-unpaid","clientName":"Harbor Title","signerName":"Harbor unpaid signer","appointmentDate":"2026-11-02","invoiceNumber":"RPT-1","originalAmount":250.25,"amountPaid":0,"amountDue":250.25,"daysOutstanding":10,"paymentStatus":"Pending"}]}"#
        case "/api/reports/mileage":
            #"{"totals":{"totalBusinessMiles":25.5,"totalTrips":2,"ordersWithMileage":2,"averageMilesPerOrder":7.75,"mileageRate":null,"estimatedMileageDeduction":null},"byMonth":[{"period":"2026-11","businessMiles":25.5,"orderMiles":15.5,"loggedMiles":10,"trips":2}],"records":{"orderMileage":[{"orderId":"harbor-unpaid","clientName":"Harbor Title","signerName":"Harbor unpaid signer","appointmentDate":"2026-11-02","miles":15.5}],"mileageLogs":[]}}"#
        case "/api/reports/expenses":
            #"{"totals":{"totalExpenses":25.75,"expenseCount":3,"averageExpense":8.58},"byCategory":[{"category":"Paper","amount":25.75,"count":3,"percentage":100}],"byMonth":[{"period":"2026-11","amount":25.75,"count":3}],"expenses":[{"date":"2026-11-02","description":"Report supplies","category":"Paper","originalAmount":25.75,"amount":25.75,"businessUsePercent":100}]}"#
        case "/api/reports/clients":
            #"{"clients":[{"clientId":"client-harbor","clientName":"Harbor Title","totalOrders":3,"completedOrders":2,"grossRevenue":300.3,"collectedRevenue":100.1,"outstandingRevenue":200.2,"averageSigningFee":150.15,"totalMileage":15.5,"averageMilesPerOrder":7.75,"averagePaymentDays":15}],"rankings":{}}"#
        default: nil
        }
    }
}
#endif

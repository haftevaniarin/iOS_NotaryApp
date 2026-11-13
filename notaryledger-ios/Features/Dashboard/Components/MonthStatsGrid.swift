import SwiftUI

struct MonthStatsGrid: View {
    let stats: MonthStats
    let month: String
    let previousMonth: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.nlViewportWidth) private var viewportWidth
    private var columns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: 10), count: dynamicTypeSize.isAccessibilitySize || viewportWidth < 360 ? 1 : 2) }
    private var positiveIncome: Bool { (stats.netIncomeChangePercent ?? -1) >= 0 }
    private var incomeCaption: String {
        guard let change = stats.netIncomeChangePercent else { return "After recorded expenses" }
        return (change > 0 ? "+" : "") + change.formatted(.number.precision(.fractionLength(0))) + "% vs \(previousMonth)"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) { heading; monthName }
            } else {
                HStack(alignment: .firstTextBaseline) { heading; Spacer(minLength: 8); monthName }
            }
            LazyVGrid(columns: columns, spacing: 10) {
                stat("Net income", value: stats.netIncome.formatted(.currency(code: stats.currencyCode)), caption: incomeCaption, positive: positiveIncome)
                stat("Signings", value: stats.signings.formatted(), caption: "Logged this month")
                stat("Mileage", value: stats.mileage.formatted(.number.precision(.fractionLength(0...1))) + " mi", caption: "Business miles logged")
                stat("Expenses", value: stats.expenses.formatted(.currency(code: stats.currencyCode)), caption: "Recorded this month")
            }
        }.foregroundStyle(Color.ink)
    }
    private var heading: some View { Text("This month").font(DashboardTheme.heading()).accessibilityAddTraits(.isHeader) }
    private var monthName: some View { Text(month).font(DashboardTheme.body(13)).foregroundStyle(Color.muted) }
    private func stat(_ label: String, value: String, caption: String, positive: Bool = false) -> some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 6) {
                Text(label).font(DashboardTheme.body(12)).foregroundStyle(Color.muted)
                Text(value).font(DashboardTheme.heading(26)).foregroundStyle(Color.ink).fixedSize(horizontal: false, vertical: true)
                Text(caption).font(DashboardTheme.body(12)).foregroundStyle(positive ? Color.positive : Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
        }.accessibilityElement(children: .ignore).accessibilityLabel("\(label), \(value), \(caption)")
            .accessibilityIdentifier("dashboard-stat-" + label.lowercased().replacingOccurrences(of: " ", with: "-"))
    }
}

import SwiftUI

struct TaxSummaryView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedYear = Calendar.current.component(.year, from: Date())
    @State private var summary: TaxSummary?
    @State private var errorMessage = ""
    @State private var isLoading = false
    @State private var exportItem: ShareURL?

    private var years: [Int] {
        let orderYears = appState.orders.compactMap { DateParser.date(from: $0.date) }.map {
            Calendar.current.component(.year, from: $0)
        }
        let expenseYears = appState.expenses.compactMap { DateParser.date(from: $0.date) }.map {
            Calendar.current.component(.year, from: $0)
        }
        return Array(Set(orderYears + expenseYears + [selectedYear])).sorted(by: >)
    }

    var body: some View {
        ZStack {
            ParchmentBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: NLSpacing.lg) {
                    ScreenTitleBlock(title: "Tax Summary", subtitle: "Review annual income, expenses, mileage, and estimated tax areas.")

                    NLCard {
                        VStack(alignment: .leading, spacing: NLSpacing.md) {
                            Text("Tax Year")
                                .font(.headline)
                                .foregroundColor(NLColor.navy)
                            Picker("Year", selection: $selectedYear) {
                                ForEach(years, id: \.self) { year in
                                    Text(String(year)).tag(year)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(NLColor.navy)
                        }
                    }

                    NavigationLink("Manage Estimated Tax Payments") { EstimatedTaxPaymentsView(year: selectedYear) { await loadSummary() } }.buttonStyle(SecondaryButtonStyle())

                    if isLoading {
                        ProgressView("Loading tax summary...")
                            .frame(maxWidth: .infinity)
                    }

                    ErrorBanner(message: errorMessage)

                    if let summary {
                        TaxSummaryCard(title: "Income", rows: [
                            ("Income Received", summary.incomeReceived.currencyString),
                            ("Unpaid Income", summary.unpaidIncome.currencyString),
                            ("Notarial Act Fee Exempt Portion", summary.notarialActFeeExemptPortion.currencyString)
                        ])
                        TaxSummaryCard(title: "Expense Summary", rows: [
                            ("Business Expenses", summary.businessExpenses.currencyString),
                            ("Travel Expenses", summary.travelExpenses.currencyString)
                        ])
                        TaxSummaryCard(title: "Travel / Mileage Totals", rows: [
                            ("Mileage", String(format: "%.2f mi", summary.totalBusinessMiles)),
                            ("Parking and order expenses", summary.travelExpenses.currencyString)
                        ])
                        TaxSummaryCard(title: "Estimated Tax", rows: [
                            ("Net Self-Employment Income", summary.netSelfEmploymentIncome.currencyString),
                            ("Self-Employment Taxable Income", summary.selfEmploymentTaxableIncome.currencyString),
                            ("Estimated Self-Employment Tax", summary.estimatedSelfEmploymentTax.currencyString),
                            ("Estimated Tax Payments", summary.estimatedTaxPayments.currencyString)
                        ])

                        Button {
                            exportPDF()
                        } label: {
                            Label("Export Tax PDF", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                }
                .padding(NLSpacing.lg)
            }
            .refreshable {
                await loadSummary()
            }
        }
        .sheet(item: $exportItem) { item in
            ShareSheet(activityItems: [item.url])
        }
        .task(id: selectedYear) { await loadSummary() }
    }

    private func loadSummary() async {
        errorMessage = ""
        summary = nil
        isLoading = true
        defer { isLoading = false }
        let year = selectedYear
        do {
            let result = try await APIService.shared.fetchTaxSummary(taxYear: year)
            try Task.checkCancellation()
            guard selectedYear == year else { return }
            summary = result
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func exportPDF() {
        guard let summary else { return }
        let data = LedgerPDF.document(title: "Tax Summary \(selectedYear)", lines: [
            appState.currentUser?.fullName ?? "Notary Ledger",
            appState.currentUser?.email ?? "",
            "Income received: \(summary.incomeReceived.currencyString)",
            "Unpaid income: \(summary.unpaidIncome.currencyString)",
            "Notarial act fees exempt from SE tax: \(summary.notarialActFeeExemptPortion.currencyString)",
            "Business expenses: \(summary.businessExpenses.currencyString)",
            "Travel expenses: \(summary.travelExpenses.currencyString)",
            String(format: "Business miles: %.2f", summary.totalBusinessMiles),
            "Net self-employment income: \(summary.netSelfEmploymentIncome.currencyString)",
            "SE taxable income: \(summary.selfEmploymentTaxableIncome.currencyString)",
            "Estimated SE tax: \(summary.estimatedSelfEmploymentTax.currencyString)",
            "Estimated tax payments: \(summary.estimatedTaxPayments.currencyString)"
        ])
        let filename = "notary-ledger-tax-summary-\(selectedYear).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: url)
            exportItem = ShareURL(url: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct TaxSummaryCard: View {
    let title: String
    let rows: [(String, String)]

    var body: some View {
        NLCard {
            VStack(alignment: .leading, spacing: NLSpacing.md) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(NLColor.navy)
                ForEach(rows, id: \.0) { row in
                    DetailRow(label: row.0, value: row.1)
                }
            }
        }
    }
}

struct ShareURL: Identifiable {
    let id = UUID()
    let url: URL
}

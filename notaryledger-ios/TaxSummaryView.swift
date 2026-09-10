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
                            ("Mileage", String(format: "%.1f mi", appState.orders.reduce(0) { $0 + ($1.mileage ?? 0) })),
                            ("Travel fees", summary.travelExpenses.currencyString)
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
        .task {
            await loadSummary()
        }
        .onChange(of: selectedYear) { _, _ in
            Task { await loadSummary() }
        }
    }

    private func loadSummary() async {
        errorMessage = ""
        isLoading = true
        defer { isLoading = false }
        do {
            summary = try await APIService.shared.fetchTaxSummary(taxYear: selectedYear)
        } catch {
            summary = FinancialSummary.localTaxSummary(orders: appState.orders, expenses: appState.expenses, year: selectedYear)
            errorMessage = "Using local totals because the backend tax summary is unavailable: \(error.localizedDescription)"
        }
    }

    private func exportPDF() {
        let user = appState.currentUser
        let data = TaxPDFGenerator.generatePDF(
            options: TaxPDFGenerator.Options(
                userFullName: user?.fullName ?? "Notary Ledger User",
                userEmail: user?.email ?? "",
                year: selectedYear,
                orders: appState.orders
            )
        )
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

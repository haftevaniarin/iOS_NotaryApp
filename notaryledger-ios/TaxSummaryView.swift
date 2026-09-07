import SwiftUI

struct TaxSummaryView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedYear = Calendar.current.component(.year, from: Date())
    @State private var summary: TaxSummary?
    @State private var errorMessage = ""
    @State private var isLoading = false

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
            List {
                Section("Tax Year") {
                    Picker("Year", selection: $selectedYear) {
                        ForEach(years, id: \.self) { year in
                            Text(String(year)).tag(year)
                        }
                    }
                }

                if isLoading {
                    Section {
                        ProgressView("Loading tax summary...")
                    }
                }

                if !errorMessage.isEmpty {
                    Section {
                        ErrorBanner(message: errorMessage)
                    }
                    .listRowBackground(Color.clear)
                }

                if let summary {
                    Section("Income") {
                        TaxRow(label: "Income Received", value: summary.incomeReceived)
                        TaxRow(label: "Unpaid Income", value: summary.unpaidIncome)
                        TaxRow(label: "Notarial Act Fee Exempt Portion", value: summary.notarialActFeeExemptPortion)
                    }
                    Section("Expenses") {
                        TaxRow(label: "Business Expenses", value: summary.businessExpenses)
                        TaxRow(label: "Travel Expenses", value: summary.travelExpenses)
                    }
                    Section("Self-Employment") {
                        TaxRow(label: "Net Self-Employment Income", value: summary.netSelfEmploymentIncome)
                        TaxRow(label: "Self-Employment Taxable Income", value: summary.selfEmploymentTaxableIncome)
                        TaxRow(label: "Estimated Self-Employment Tax", value: summary.estimatedSelfEmploymentTax)
                        TaxRow(label: "Estimated Tax Payments", value: summary.estimatedTaxPayments)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .refreshable {
                await loadSummary()
            }
        }
        .navigationTitle("Tax Summary")
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
}

struct TaxRow: View {
    let label: String
    let value: Double

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(NLColor.muted)
            Spacer()
            Text(value.currencyString)
                .foregroundColor(NLColor.navy)
                .fontWeight(.semibold)
        }
    }
}

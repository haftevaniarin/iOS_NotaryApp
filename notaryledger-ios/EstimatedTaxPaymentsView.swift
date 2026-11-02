import SwiftUI

struct EstimatedTaxPaymentsView: View {
    let year: Int
    let onChange: () async -> Void
    @State private var payments: [EstimatedTaxPayment] = []
    @State private var editor: EstimatedTaxPayment?
    @State private var showEditor = false
    @State private var deleting: EstimatedTaxPayment?
    @State private var error = ""
    @State private var busy = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NLSpacing.lg) {
                ScreenTitleBlock(title: "Estimated Tax Payments", subtitle: String(year))
                ErrorBanner(message: error)
                Button("Add Payment") { editor = nil; showEditor = true }.buttonStyle(PrimaryButtonStyle()).disabled(busy)
                if busy { ProgressView() }
                ForEach(payments.filter { $0.taxYear == year }) { payment in
                    NLCard {
                        VStack(alignment: .leading, spacing: NLSpacing.md) {
                            DetailRow(label: payment.quarter, value: payment.amount.currencyString)
                            DetailRow(label: "Paid", value: payment.date)
                            HStack {
                                Button("Edit") { editor = payment; showEditor = true }
                                Spacer()
                                Button("Delete", role: .destructive) { deleting = payment }
                            }.disabled(busy)
                        }
                    }
                }
            }.padding(NLSpacing.lg)
        }.background(ParchmentBackground()).task { await load() }.refreshable { await load() }
            .sheet(isPresented: $showEditor) { NavigationStack { PaymentEditor(payment: editor, year: year) { payload in
                _ = try await APIService.shared.saveTaxPayment(id: editor?.id, payload: payload)
                await load(); await onChange()
            } } }
            .sheet(item: $deleting) { payment in
                DeleteConfirmationSheet(title: "Delete Tax Payment", message: "Delete this \(payment.quarter) tax payment?") { Task { await delete(payment) } }
            }
    }
    private func load() async {
        busy = true; error = ""
        defer { busy = false }
        do { payments = try await APIService.shared.fetchTaxPayments() }
        catch { self.error = error.localizedDescription }
    }
    private func delete(_ payment: EstimatedTaxPayment) async {
        busy = true; error = ""
        defer { busy = false }
        do { try await APIService.shared.deleteTaxPayment(id: payment.id); payments.removeAll { $0.id == payment.id }; await onChange() }
        catch { self.error = error.localizedDescription }
    }
}

private struct PaymentEditor: View {
    @Environment(\.dismiss) private var dismiss
    let payment: EstimatedTaxPayment?
    let year: Int
    let onSave: (EstimatedTaxPaymentPayload) async throws -> Void
    @State private var date = Date()
    @State private var amount = ""
    @State private var quarter = "Q1"
    @State private var error = ""
    @State private var busy = false
    var body: some View {
        Form {
            Section("Tax payment for \(String(year))") {
                DatePicker("Payment date", selection: $date, displayedComponents: .date)
                TextField("Amount", text: $amount).keyboardType(.decimalPad)
                Picker("Quarter", selection: $quarter) { ForEach(["Q1", "Q2", "Q3", "Q4"], id: \.self) { Text($0).tag($0) } }
                ErrorBanner(message: error)
            }
        }.navigationTitle(payment == nil ? "Add Tax Payment" : "Edit Tax Payment")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() }.disabled(busy) }
                ToolbarItem(placement: .topBarTrailing) { Button("Save") { Task { await save() } }.disabled(busy) }
            }
            .onAppear { if let payment { date = DateParser.date(from: payment.date) ?? Date(); amount = String(payment.amount); quarter = payment.quarter } }
    }
    private func save() async {
        guard let value = Double(amount), value.isFinite, value >= 0 else { error = "Enter a valid payment amount."; return }
        error = ""; busy = true
        defer { busy = false }
        do { try await onSave(EstimatedTaxPaymentPayload(date: DateParser.apiDateString(from: date), amount: value, quarter: quarter, taxYear: year)); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

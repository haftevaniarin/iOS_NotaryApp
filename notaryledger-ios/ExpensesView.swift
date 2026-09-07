import SwiftUI

struct ExpensesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var searchText = ""
    @State private var showForm = false
    @State private var editingExpense: Expense?
    @State private var deletingExpense: Expense?
    @State private var errorMessage = ""

    private var filteredExpenses: [Expense] {
        appState.expenses.filter { expense in
            searchText.isEmpty ||
            "\(expense.category) \(expense.description)".lowercased().contains(searchText.lowercased())
        }
    }

    var body: some View {
        ZStack {
            ParchmentBackground()
            List {
                if !errorMessage.isEmpty {
                    Section {
                        ErrorBanner(message: errorMessage)
                    }
                    .listRowBackground(Color.clear)
                }

                if filteredExpenses.isEmpty {
                    Section {
                        EmptyStateView(title: "No expenses found", systemImage: "creditcard", message: "Track supplies, software, mileage, and business costs.")
                    }
                    .listRowBackground(Color.clear)
                } else {
                    Section("Expenses") {
                        ForEach(filteredExpenses) { expense in
                            ExpenseRow(expense: expense)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    editingExpense = expense
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        deletingExpense = expense
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    Button {
                                        editingExpense = expense
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    .tint(NLColor.brass)
                                }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .searchable(text: $searchText, prompt: "Search expenses")
            .refreshable {
                await appState.refreshAll()
            }
        }
        .navigationTitle("Expenses")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showForm = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add expense")
            }
        }
        .sheet(isPresented: $showForm) {
            NavigationStack {
                ExpenseFormView(expense: nil) { payload in
                    let created = try await APIService.shared.createExpense(payload)
                    await MainActor.run {
                        appState.upsertExpense(created)
                    }
                }
            }
        }
        .sheet(item: $editingExpense) { expense in
            NavigationStack {
                ExpenseFormView(expense: expense) { payload in
                    let updated = try await APIService.shared.updateExpense(expenseId: expense.id, expense: payload)
                    await MainActor.run {
                        appState.upsertExpense(updated)
                    }
                }
            }
        }
        .sheet(item: $deletingExpense) { expense in
            DeleteConfirmationSheet(
                title: "Delete Expense",
                message: "Delete \(expense.description)? This cannot be undone."
            ) {
                Task { await delete(expense) }
            }
        }
    }

    private func delete(_ expense: Expense) async {
        do {
            try await APIService.shared.deleteExpense(expenseId: expense.id)
            appState.removeExpense(id: expense.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ExpenseRow: View {
    let expense: Expense

    var body: some View {
        HStack(alignment: .top, spacing: NLSpacing.md) {
            VStack(alignment: .leading, spacing: NLSpacing.xs) {
                Text(expense.description)
                    .font(.headline)
                    .foregroundColor(NLColor.ink)
                    .lineLimit(1)
                Text(expense.category)
                    .font(.subheadline)
                    .foregroundColor(NLColor.muted)
                Text(DateParser.date(from: expense.date).map { Formatters.displayDate.string(from: $0) } ?? expense.date)
                    .font(.caption)
                    .foregroundColor(NLColor.muted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: NLSpacing.xs) {
                Text(expense.amount.currencyString)
                    .font(.headline)
                    .foregroundColor(NLColor.navy)
                Text("\(Int(expense.businessUsePercent))% business")
                    .font(.caption)
                    .foregroundColor(NLColor.brass)
            }
        }
        .padding(.vertical, 6)
    }
}

struct ExpenseFormView: View {
    @Environment(\.dismiss) private var dismiss
    let expense: Expense?
    let onSave: (ExpensePayload) async throws -> Void

    @State private var date = Date()
    @State private var category = "Supplies"
    @State private var description = ""
    @State private var amount = ""
    @State private var businessUsePercent = 100.0
    @State private var errorMessage = ""
    @State private var isSaving = false

    private let categories = ["Supplies", "Software", "Mileage", "Travel", "Education", "Insurance", "Marketing", "Other"]

    var body: some View {
        ZStack {
            ParchmentBackground()
            Form {
                Section("Expense") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    Picker("Category", selection: $category) {
                        ForEach(categories, id: \.self) { category in
                            Text(category).tag(category)
                        }
                    }
                    TextField("Description", text: $description)
                    TextField("Amount", text: $amount)
                        .keyboardType(.decimalPad)
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Business use")
                            Spacer()
                            Text("\(Int(businessUsePercent))%")
                                .foregroundColor(NLColor.muted)
                        }
                        Slider(value: $businessUsePercent, in: 0...100, step: 5)
                    }
                }

                if !errorMessage.isEmpty {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(expense == nil ? "New Expense" : "Edit Expense")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(isSaving ? "Saving..." : "Save") {
                    Task { await save() }
                }
                .disabled(isSaving)
            }
        }
        .onAppear(perform: populate)
    }

    private func populate() {
        guard let expense else { return }
        date = DateParser.date(from: expense.date) ?? Date()
        category = expense.category.isEmpty ? "Other" : expense.category
        description = expense.description
        amount = String(format: "%.2f", expense.amount)
        businessUsePercent = expense.businessUsePercent
    }

    private func save() async {
        errorMessage = ""
        guard !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Enter a description."
            return
        }
        guard let amountValue = Double(amount), amountValue >= 0 else {
            errorMessage = "Enter a valid amount."
            return
        }

        let payload = ExpensePayload(
            date: DateParser.apiDateString(from: date),
            category: category,
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            amount: amountValue,
            businessUsePercent: businessUsePercent
        )

        isSaving = true
        defer { isSaving = false }
        do {
            try await onSave(payload)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

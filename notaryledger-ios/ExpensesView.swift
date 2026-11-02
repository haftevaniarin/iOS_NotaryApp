import SwiftUI
import UniformTypeIdentifiers

struct ExpensesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var searchText = ""
    @State private var showForm = false
    @State private var showReceiptExtraction = false
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
            ScrollView {
                VStack(alignment: .leading, spacing: NLSpacing.lg) {
                    ScreenTitleBlock(title: "Expenses", subtitle: "Search, log, edit, and review deductible business costs.")
                    ErrorBanner(message: errorMessage)

                    NLTextField(title: "Search expenses", text: $searchText)
                        .nlPanel()

                    HStack(spacing: NLSpacing.md) {
                        Button {
                            showForm = true
                        } label: {
                            ActionPill(title: "Log Expense", systemImage: "plus")
                        }
                        Button {
                            showReceiptExtraction = true
                        } label: {
                            ActionPill(title: "Receipt Scan", systemImage: "doc.viewfinder")
                        }
                    }

                    if appState.isLoading {
                        ProgressView("Loading expenses...")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 32)
                    }

                    if filteredExpenses.isEmpty {
                        EmptyStateView(title: "No expenses found", systemImage: "creditcard", message: "Track supplies, software, mileage, and business costs.")
                    } else {
                        SectionHeader(title: "Expenses")
                        ForEach(filteredExpenses) { expense in
                            ExpenseCard(
                                expense: expense,
                                onEdit: { editingExpense = expense },
                                onDelete: { deletingExpense = expense }
                            )
                        }
                    }
                }
                .padding(NLSpacing.lg)
            }
            .refreshable {
                await appState.refreshAll()
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
        .sheet(isPresented: $showReceiptExtraction) {
            ReceiptExtractionSheet()
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

struct ExpenseCard: View {
    let expense: Expense
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        NLCard {
            VStack(alignment: .leading, spacing: NLSpacing.md) {
                HStack(alignment: .top, spacing: NLSpacing.md) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(expense.description)
                            .font(.headline)
                            .foregroundColor(NLColor.ink)
                            .lineLimit(1)
                        Text(expense.category)
                            .font(.subheadline)
                            .foregroundColor(NLColor.muted)
                    }
                    Spacer()
                    Text(expense.amount.currencyString)
                        .font(.headline)
                        .foregroundColor(NLColor.navy)
                }

                DetailRow(label: "Date", value: DateParser.date(from: expense.date).map { Formatters.displayDate.string(from: $0) } ?? expense.date)
                DetailRow(label: "Deductible", value: expense.businessUsePercent > 0 ? "Yes, \(Int(expense.businessUsePercent))%" : "No")

                HStack(spacing: NLSpacing.sm) {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .frame(width: 36, height: 36)
                    }
                    Spacer()
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                            .frame(width: 36, height: 36)
                    }
                }
                .buttonStyle(.bordered)
                .tint(NLColor.navy)
            }
        }
    }
}

struct ExpenseFormView: View {
    @Environment(\.dismiss) private var dismiss
    let expense: Expense?
    let onSave: (ExpensePayload) async throws -> Void
    var extracted: ExtractedExpense? = nil
    var linkedToOrder = false

    @State private var date = Date()
    @State private var category = "Office supplies"
    @State private var description = ""
    @State private var amount = ""
    @State private var deductible = true
    @State private var businessUsePercent = 100.0
    @State private var errorMessage = ""
    @State private var isSaving = false

    private let categories = ["Paper", "Toner", "Printer and scanner costs", "Shipping", "Parking and tolls", "Background checks", "Commission, bond and E&O insurance", "Training and certifications", "Advertising", "Phone and internet", "Software subscriptions", "Office supplies", "Other"]

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
                    if !linkedToOrder {
                    Toggle("Deductible", isOn: $deductible)
                        .tint(NLColor.navy)
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Business use")
                            Spacer()
                            Text("\(Int(businessUsePercent))%")
                                .foregroundColor(NLColor.muted)
                        }
                        Slider(value: $businessUsePercent, in: 0...100, step: 5)
                            .disabled(!deductible)
                    }
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
        if let extracted {
            category = categories.contains(extracted.category ?? "") ? extracted.category! : "Other"
            description = extracted.description ?? ""
            amount = extracted.amount.map { String($0) } ?? ""
            date = DateParser.date(from: extracted.date) ?? Date()
            businessUsePercent = extracted.businessUsePercent ?? 100
            deductible = businessUsePercent > 0
            return
        }
        guard let expense else { return }
        date = DateParser.date(from: expense.date) ?? Date()
        category = expense.category.isEmpty ? "Other" : expense.category
        description = expense.description
        amount = String(format: "%.2f", expense.amount)
        deductible = expense.businessUsePercent > 0
        businessUsePercent = expense.businessUsePercent
    }

    private func save() async {
        errorMessage = ""
        guard !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Enter a description."
            return
        }
        guard let amountValue = Double(amount), amountValue.isFinite, amountValue >= 0 else {
            errorMessage = "Enter a valid amount."
            return
        }

        let payload = ExpensePayload(
            date: DateParser.apiDateString(from: date),
            category: category,
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            amount: amountValue,
            businessUsePercent: deductible ? businessUsePercent : 0
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

struct ReceiptExtractionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @State private var showImporter = false
    @State private var busy = false
    @State private var error = ""
    @State private var draft: ExtractedExpense?
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: NLSpacing.lg) {
                ScreenTitleBlock(title: "Receipt Extraction", subtitle: "Choose a JPEG, PNG, or WebP receipt, then review and save the extracted details.")
                ErrorBanner(message: error)
                Button(busy ? "Extracting..." : "Choose Receipt Image") { showImporter = true }.buttonStyle(PrimaryButtonStyle()).disabled(busy)
                if busy { ProgressView() }
                Spacer()
            }.padding().background(ParchmentBackground())
                .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() }.disabled(busy) } }
                .fileImporter(isPresented: $showImporter, allowedContentTypes: [.jpeg, .png, .webP]) { result in
                    switch result {
                    case .success(let url): Task { await extract(url) }
                    case .failure(let failure): error = failure.localizedDescription
                    }
                }
                .sheet(item: $draft) { extracted in
                    NavigationStack {
                        ExpenseFormView(expense: nil, onSave: { payload in
                            let expense = try await APIService.shared.createExpense(payload)
                            appState.upsertExpense(expense); dismiss()
                        }, extracted: extracted)
                    }
                }
        }
    }
    private func extract(_ url: URL) async {
        error = ""; busy = true
        defer { busy = false }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 10 * 1024 * 1024 else { throw APIError.serverError("Choose a file of 10 MB or smaller.") }
            let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? ""
            draft = try await APIService.shared.extractExpense(MultipartFile(fieldName: "file", fileName: url.lastPathComponent, mimeType: mime, data: Data(contentsOf: url)))
        } catch { self.error = error.localizedDescription }
    }
}

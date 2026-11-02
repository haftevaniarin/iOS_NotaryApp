import SwiftUI

struct OrderExpensesView: View {
    let order: SigningOrder
    @State private var expenses: [Expense] = []
    @State private var editing: Expense?
    @State private var deleting: Expense?
    @State private var showForm = false
    @State private var error = ""
    @State private var busy = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NLSpacing.lg) {
                ScreenTitleBlock(title: "Signing Expenses", subtitle: order.customerName)
                ErrorBanner(message: error)
                Button("Add Signing Expense") { editing = nil; showForm = true }.buttonStyle(PrimaryButtonStyle()).disabled(busy)
                if busy { ProgressView() }
                ForEach(expenses) { expense in
                    ExpenseCard(expense: expense, onEdit: { editing = expense; showForm = true }, onDelete: { deleting = expense })
                }
            }.padding(NLSpacing.lg)
        }.background(ParchmentBackground()).task { await load() }.refreshable { await load() }
            .sheet(isPresented: $showForm) {
                NavigationStack {
                    ExpenseFormView(expense: editing, onSave: { payload in
                        let updated = try await APIService.shared.saveOrderExpense(orderId: order.id, expenseId: editing?.id, payload: payload)
                        if let index = expenses.firstIndex(where: { $0.id == updated.id }) { expenses[index] = updated } else { expenses.append(updated) }
                    }, linkedToOrder: true)
                }
            }
            .sheet(item: $deleting) { expense in
                DeleteConfirmationSheet(title: "Delete Signing Expense", message: "Delete \(expense.description)?") { Task { await delete(expense) } }
            }
    }
    private func load() async {
        busy = true; error = ""
        defer { busy = false }
        do { expenses = try await APIService.shared.fetchOrderExpenses(orderId: order.id) }
        catch { self.error = error.localizedDescription }
    }
    private func delete(_ expense: Expense) async {
        busy = true; error = ""
        defer { busy = false }
        do { try await APIService.shared.deleteOrderExpense(orderId: order.id, expenseId: expense.id); expenses.removeAll { $0.id == expense.id } }
        catch { self.error = error.localizedDescription }
    }
}

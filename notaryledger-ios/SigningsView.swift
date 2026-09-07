import SwiftUI

struct SigningsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var searchText = ""
    @State private var selectedStatus: SigningStatus?
    @State private var showForm = false
    @State private var editingOrder: SigningOrder?
    @State private var deletingOrder: SigningOrder?
    @State private var errorMessage = ""

    private var filteredOrders: [SigningOrder] {
        appState.orders.filter { order in
            let matchesStatus = selectedStatus == nil || order.normalizedStatus == selectedStatus
            let haystack = [order.customerName, order.payerName, order.signerName, order.signingType, order.invoiceNumber]
                .compactMap { $0 }
                .joined(separator: " ")
                .lowercased()
            let matchesSearch = searchText.isEmpty || haystack.contains(searchText.lowercased())
            return matchesStatus && matchesSearch
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

                Section {
                    Picker("Status", selection: $selectedStatus) {
                        Text("All").tag(SigningStatus?.none)
                        ForEach(SigningStatus.allCases) { status in
                            Text(status.rawValue).tag(Optional(status))
                        }
                    }
                    .pickerStyle(.menu)
                }
                .listRowBackground(NLColor.panel)

                if filteredOrders.isEmpty {
                    Section {
                        EmptyStateView(title: "No signings found", systemImage: "doc.text.magnifyingglass", message: "Adjust search or create a new signing order.")
                    }
                    .listRowBackground(Color.clear)
                } else {
                    Section("Signing Orders") {
                        ForEach(filteredOrders) { order in
                            NavigationLink {
                                SigningOrderDetailView(order: order)
                            } label: {
                                SigningOrderListRow(order: order)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    deletingOrder = order
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    editingOrder = order
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
            .searchable(text: $searchText, prompt: "Search customer, payer, signer, invoice")
            .refreshable {
                await appState.refreshAll()
            }
        }
        .navigationTitle("Signings")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showForm = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add signing")
            }
        }
        .sheet(isPresented: $showForm) {
            NavigationStack {
                SigningOrderFormView(order: nil) { payload in
                    let created = try await APIService.shared.createOrder(payload)
                    await MainActor.run {
                        appState.upsertOrder(created)
                    }
                }
            }
        }
        .sheet(item: $editingOrder) { order in
            NavigationStack {
                SigningOrderFormView(order: order) { payload in
                    let updated = try await APIService.shared.updateOrder(orderId: order.id, order: payload)
                    await MainActor.run {
                        appState.upsertOrder(updated)
                    }
                }
            }
        }
        .sheet(item: $deletingOrder) { order in
            DeleteConfirmationSheet(
                title: "Delete Signing",
                message: "Delete the signing for \(order.customerName)? This cannot be undone."
            ) {
                Task { await delete(order) }
            }
        }
    }

    private func delete(_ order: SigningOrder) async {
        do {
            try await APIService.shared.deleteOrder(orderId: order.id)
            appState.removeOrder(id: order.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct SigningOrderListRow: View {
    let order: SigningOrder

    var body: some View {
        VStack(alignment: .leading, spacing: NLSpacing.sm) {
            HStack {
                Text(order.customerName)
                    .font(.headline)
                    .foregroundColor(NLColor.ink)
                Spacer()
                StatusBadge(status: order.normalizedStatus)
            }
            Text("Signer: \(order.signerName)")
                .font(.subheadline)
                .foregroundColor(NLColor.muted)
            HStack {
                Text([order.displayDate, order.time].compactMap { $0 }.joined(separator: " at "))
                Spacer()
                Text(order.fee.currencyString)
                    .fontWeight(.semibold)
                    .foregroundColor(NLColor.navy)
            }
            .font(.subheadline)
        }
        .padding(.vertical, 6)
    }
}

struct SigningOrderDetailView: View {
    @EnvironmentObject private var appState: AppState
    let order: SigningOrder
    @State private var editingOrder: SigningOrder?

    private var liveOrder: SigningOrder {
        appState.orders.first(where: { $0.id == order.id }) ?? order
    }

    var body: some View {
        ZStack {
            ParchmentBackground()
            Form {
                Section("Signing") {
                    DetailRow(label: "Customer", value: liveOrder.customerName)
                    DetailRow(label: "Payer", value: liveOrder.payerName ?? "")
                    DetailRow(label: "Signer", value: liveOrder.signerName)
                    DetailRow(label: "Type", value: liveOrder.signingType ?? "")
                    DetailRow(label: "Date", value: liveOrder.displayDate)
                    DetailRow(label: "Time", value: liveOrder.time ?? "")
                    DetailRow(label: "Status", value: liveOrder.normalizedStatus.rawValue)
                }
                Section("Payment") {
                    DetailRow(label: "Fee", value: liveOrder.fee.currencyString)
                    DetailRow(label: "Notarial Act Fee", value: liveOrder.notarialActFee.currencyString)
                    DetailRow(label: "Paid", value: liveOrder.paid ? "Yes" : "No")
                    DetailRow(label: "Paid Date", value: liveOrder.paidDate ?? "")
                    DetailRow(label: "Invoice", value: liveOrder.invoiceNumber)
                }
                Section("Travel") {
                    DetailRow(label: "Mileage", value: liveOrder.mileage.map { String(format: "%.1f mi", $0) } ?? "")
                    DetailRow(label: "Travel Fee", value: liveOrder.travelFee?.currencyString ?? "")
                }
                Section("Notes") {
                    Text(liveOrder.notes?.isEmpty == false ? liveOrder.notes! : "-")
                        .foregroundColor(NLColor.ink)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Signing Detail")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editingOrder = liveOrder
                } label: {
                    Image(systemName: "pencil")
                }
                .accessibilityLabel("Edit signing")
            }
        }
        .sheet(item: $editingOrder) { order in
            NavigationStack {
                SigningOrderFormView(order: order) { payload in
                    let updated = try await APIService.shared.updateOrder(orderId: order.id, order: payload)
                    await MainActor.run {
                        appState.upsertOrder(updated)
                    }
                }
            }
        }
    }
}

struct SigningOrderFormView: View {
    @Environment(\.dismiss) private var dismiss
    let order: SigningOrder?
    let onSave: (SigningOrderPayload) async throws -> Void

    @State private var customerName = ""
    @State private var payerName = ""
    @State private var signerName = ""
    @State private var signingType = ""
    @State private var date = Date()
    @State private var time = ""
    @State private var fee = ""
    @State private var notarialActFee = ""
    @State private var paid = false
    @State private var paidDate = Date()
    @State private var hasPaidDate = false
    @State private var invoiceNumber = ""
    @State private var notes = ""
    @State private var mileage = ""
    @State private var travelFee = ""
    @State private var status: SigningStatus = .scheduled
    @State private var errorMessage = ""
    @State private var isSaving = false

    var body: some View {
        ZStack {
            ParchmentBackground()
            Form {
                Section("Parties") {
                    TextField("Customer name", text: $customerName)
                    TextField("Payer name", text: $payerName)
                    TextField("Signer name", text: $signerName)
                    TextField("Signing type", text: $signingType)
                }
                Section("Schedule") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField("Time", text: $time)
                    Picker("Status", selection: $status) {
                        ForEach(SigningStatus.allCases) { status in
                            Text(status.rawValue).tag(status)
                        }
                    }
                }
                Section("Payment") {
                    TextField("Fee", text: $fee)
                        .keyboardType(.decimalPad)
                    TextField("Notarial act fee", text: $notarialActFee)
                        .keyboardType(.decimalPad)
                    Toggle("Paid", isOn: $paid)
                        .disabled(status == .cancelled)
                    Toggle("Has paid date", isOn: $hasPaidDate)
                        .disabled(status == .cancelled || !paid)
                    if hasPaidDate && paid && status != .cancelled {
                        DatePicker("Paid date", selection: $paidDate, displayedComponents: .date)
                    }
                    TextField("Invoice number", text: $invoiceNumber)
                }
                Section("Travel") {
                    TextField("Mileage", text: $mileage)
                        .keyboardType(.decimalPad)
                    TextField("Travel fee", text: $travelFee)
                        .keyboardType(.decimalPad)
                }
                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 90)
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
        .navigationTitle(order == nil ? "New Signing" : "Edit Signing")
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
        .onChange(of: status) { _, newValue in
            if newValue == .cancelled {
                paid = false
                hasPaidDate = false
            } else if newValue == .paid {
                paid = true
                hasPaidDate = true
            }
        }
    }

    private func populate() {
        guard let order else { return }
        customerName = order.customerName
        payerName = order.payerName ?? ""
        signerName = order.signerName
        signingType = order.signingType ?? ""
        date = DateParser.date(from: order.date) ?? Date()
        time = order.time ?? ""
        fee = String(format: "%.2f", order.fee)
        notarialActFee = String(format: "%.2f", order.notarialActFee)
        paid = order.paid
        if let paidDateValue = DateParser.date(from: order.paidDate) {
            paidDate = paidDateValue
            hasPaidDate = true
        }
        invoiceNumber = order.invoiceNumber
        notes = order.notes ?? ""
        mileage = order.mileage.map { String(format: "%.1f", $0) } ?? ""
        travelFee = order.travelFee.map { String(format: "%.2f", $0) } ?? ""
        status = order.normalizedStatus
    }

    private func save() async {
        errorMessage = ""
        guard !customerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Enter the customer name."
            return
        }
        guard !signerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Enter the signer name."
            return
        }
        guard let feeValue = Double(fee), feeValue >= 0 else {
            errorMessage = "Enter a valid fee."
            return
        }
        guard let notarialValue = Double(notarialActFee.isEmpty ? "0" : notarialActFee), notarialValue >= 0 else {
            errorMessage = "Enter a valid notarial act fee."
            return
        }
        let mileageValue = optionalDouble(mileage)
        let travelValue = optionalDouble(travelFee)
        guard mileageValue != nil || mileage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              travelValue != nil || travelFee.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Enter valid travel values."
            return
        }

        let payload = SigningOrderPayload(
            customerName: customerName.trimmingCharacters(in: .whitespacesAndNewlines),
            payerName: nilIfBlank(payerName),
            signerName: signerName.trimmingCharacters(in: .whitespacesAndNewlines),
            signingType: nilIfBlank(signingType),
            date: DateParser.apiDateString(from: date),
            time: nilIfBlank(time),
            fee: feeValue,
            notarialActFee: notarialValue,
            paid: paid,
            paidDate: hasPaidDate && paid ? DateParser.apiDateString(from: paidDate) : nil,
            invoiceNumber: invoiceNumber.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: nilIfBlank(notes),
            mileage: mileageValue,
            travelFee: travelValue,
            status: status
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

    private func optionalDouble(_ value: String) -> Double? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return nil
        }
        return Double(trimmed)
    }

    private func nilIfBlank(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

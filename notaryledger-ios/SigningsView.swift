import SwiftUI

struct SigningsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var searchText = ""
    @State private var selectedStatus: SigningStatus?
    @State private var showForm = false
    @State private var showImport = false
    @State private var editingOrder: SigningOrder?
    @State private var deletingOrder: SigningOrder?
    @State private var mileageOrder: SigningOrder?
    @State private var invoiceOrder: SigningOrder?
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
            ScrollView {
                VStack(alignment: .leading, spacing: NLSpacing.lg) {
                    ScreenTitleBlock(title: "Signings", subtitle: "Search, filter, import, and manage signing orders.")
                    ErrorBanner(message: errorMessage)

                    VStack(alignment: .leading, spacing: NLSpacing.md) {
                        NLTextField(title: "Search", text: $searchText)
                        Picker("Status", selection: $selectedStatus) {
                            Text("All").tag(SigningStatus?.none)
                            ForEach(SigningStatus.allCases) { status in
                                Text(status.rawValue).tag(Optional(status))
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(NLColor.navy)
                    }
                    .nlPanel()

                    HStack(spacing: NLSpacing.md) {
                        Button {
                            showForm = true
                        } label: {
                            ActionPill(title: "New Signing", systemImage: "plus")
                        }
                        Button {
                            showImport = true
                        } label: {
                            ActionPill(title: "Import", systemImage: "square.and.arrow.down")
                        }
                    }

                    if appState.isLoading {
                        ProgressView("Loading signings...")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 32)
                    }

                    if filteredOrders.isEmpty {
                        EmptyStateView(title: "No signings found", systemImage: "doc.text.magnifyingglass", message: "Adjust search or create a new signing order.")
                    } else {
                        SectionHeader(title: "Signing Orders")
                        ForEach(filteredOrders) { order in
                            SigningOrderCard(
                                order: order,
                                onEdit: { editingOrder = order },
                                onMileage: { mileageOrder = order },
                                onInvoice: { invoiceOrder = order },
                                onDelete: { deletingOrder = order }
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
                SigningOrderFormView(order: nil) { payload in
                    let created = try await APIService.shared.createOrder(payload)
                    await MainActor.run {
                        appState.upsertOrder(created)
                    }
                }
            }
        }
        .sheet(isPresented: $showImport) {
            ImportSigningsSheet()
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
        .sheet(item: $mileageOrder) { order in
            MileageTravelSheet(order: order) { mileage, travelFee in
                try await updateTravel(order, mileage: mileage, travelFee: travelFee)
            }
        }
        .sheet(item: $invoiceOrder) { order in
            GenerateInvoiceSheet(order: order)
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

    private func updateTravel(_ order: SigningOrder, mileage: Double?, travelFee: Double?) async throws {
        let payload = SigningOrderPayload(
            customerName: order.customerName,
            payerName: order.payerName,
            signerName: order.signerName,
            signingType: order.signingType,
            date: order.date,
            time: order.time,
            fee: order.fee,
            notarialActFee: order.notarialActFee,
            paid: order.paid,
            paidDate: order.paidDate,
            invoiceNumber: order.invoiceNumber,
            notes: order.notes,
            mileage: mileage,
            travelFee: travelFee,
            status: order.normalizedStatus
        )
        let updated = try await APIService.shared.updateOrder(orderId: order.id, order: payload)
        await MainActor.run {
            appState.upsertOrder(updated)
        }
    }
}

struct SigningOrderCard: View {
    let order: SigningOrder
    let onEdit: () -> Void
    let onMileage: () -> Void
    let onInvoice: () -> Void
    let onDelete: () -> Void

    var body: some View {
        NLCard {
            VStack(alignment: .leading, spacing: NLSpacing.md) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(order.customerName)
                            .font(.headline)
                            .foregroundColor(NLColor.ink)
                            .lineLimit(1)
                        Text("Signer: \(order.signerName)")
                            .font(.subheadline)
                            .foregroundColor(NLColor.muted)
                    }
                    Spacer()
                    StatusBadge(status: order.normalizedStatus)
                }

                DetailRow(label: "Date", value: [order.displayDate, order.time].compactMap { $0 }.joined(separator: " at "))
                DetailRow(label: "Fee", value: order.fee.currencyString)
                DetailRow(label: "Invoice", value: order.invoiceNumber)
                DetailRow(label: "Travel", value: travelSummary)

                HStack(spacing: NLSpacing.sm) {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .frame(width: 36, height: 36)
                    }
                    Button(action: onMileage) {
                        Image(systemName: "car")
                            .frame(width: 36, height: 36)
                    }
                    Button(action: onInvoice) {
                        Image(systemName: "doc.richtext")
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

    private var travelSummary: String {
        let miles = order.mileage.map { String(format: "%.1f mi", $0) } ?? "-"
        let fee = order.travelFee?.currencyString ?? "-"
        return "\(miles) / \(fee)"
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

struct ImportSigningsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var rawText = ""
    @State private var message = ""

    var body: some View {
        NavigationStack {
            ZStack {
                ParchmentBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: NLSpacing.lg) {
                        ScreenTitleBlock(title: "Import Signings", subtitle: "Paste signing order text to review before creating ledger entries.")

                        NLCard {
                            VStack(alignment: .leading, spacing: NLSpacing.md) {
                                FieldLabel(text: "Order text")
                                TextEditor(text: $rawText)
                                    .frame(minHeight: 180)
                                    .padding(8)
                                    .background(Color.white)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(NLColor.line, lineWidth: 1)
                                    )
                                BannerView(kind: .info, message: "Imported signings should be reviewed before saving.")
                                BannerView(kind: .success, message: message)
                            }
                        }
                    }
                    .padding(NLSpacing.lg)
                }
            }
            .navigationTitle("Import Signings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Review") {
                        message = rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? ""
                            : "Import preview ready."
                    }
                    .disabled(rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.large])
    }
}

struct MileageTravelSheet: View {
    @Environment(\.dismiss) private var dismiss
    let order: SigningOrder
    let onSave: (Double?, Double?) async throws -> Void

    @State private var mileage = ""
    @State private var travelFee = ""
    @State private var errorMessage = ""
    @State private var showClearConfirmation = false
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            ZStack {
                ParchmentBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: NLSpacing.lg) {
                        ScreenTitleBlock(title: "Mileage & Travel", subtitle: order.customerName)
                        ErrorBanner(message: errorMessage)

                        NLCard {
                            VStack(spacing: NLSpacing.md) {
                                NLTextField(title: "Mileage", text: $mileage, keyboardType: .decimalPad)
                                NLTextField(title: "Travel fee", text: $travelFee, keyboardType: .decimalPad)
                                Button(role: .destructive) {
                                    showClearConfirmation = true
                                } label: {
                                    Label("Clear Mileage", systemImage: "xmark.circle")
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .padding(NLSpacing.lg)
                }
            }
            .navigationTitle("Travel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSaving ? "Saving..." : "Save") {
                        Task { await save() }
                    }
                    .disabled(isSaving)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .confirmationDialog("Clear mileage and travel fee?", isPresented: $showClearConfirmation) {
            Button("Clear Mileage", role: .destructive) {
                mileage = ""
                travelFee = ""
            }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear {
            mileage = order.mileage.map { String(format: "%.1f", $0) } ?? ""
            travelFee = order.travelFee.map { String(format: "%.2f", $0) } ?? ""
        }
    }

    private func save() async {
        errorMessage = ""
        let mileageValue = optionalDouble(mileage)
        let travelValue = optionalDouble(travelFee)
        guard mileageValue != nil || mileage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              travelValue != nil || travelFee.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Enter valid travel values."
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await onSave(mileageValue, travelValue)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func optionalDouble(_ value: String) -> Double? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        return Double(trimmed)
    }
}

struct GenerateInvoiceSheet: View {
    @Environment(\.dismiss) private var dismiss
    let order: SigningOrder
    @State private var invoice: Invoice?
    @State private var errorMessage = ""
    @State private var isGenerating = false

    var body: some View {
        NavigationStack {
            ZStack {
                ParchmentBackground()
                VStack(alignment: .leading, spacing: NLSpacing.lg) {
                    ScreenTitleBlock(title: "Generate Invoice PDF", subtitle: order.customerName)
                    ErrorBanner(message: errorMessage)

                    NLCard {
                        VStack(spacing: NLSpacing.md) {
                            DetailRow(label: "Signer", value: order.signerName)
                            DetailRow(label: "Signing date", value: order.displayDate)
                            DetailRow(label: "Balance", value: order.fee.currencyString)
                        }
                    }

                    if let invoice {
                        NLCard {
                            VStack(alignment: .leading, spacing: NLSpacing.md) {
                                DetailRow(label: "Invoice", value: invoice.invoiceNumber)
                                DetailRow(label: "Balance", value: invoice.balanceDue.currencyString)
                                if let pdfURL = invoice.pdfURL, let url = URL(string: pdfURL) {
                                    Link("Open PDF", destination: url)
                                }
                            }
                        }
                    }

                    Button(isGenerating ? "Generating..." : "Generate Invoice PDF") {
                        Task { await generate() }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(isGenerating)

                    Spacer()
                }
                .padding(NLSpacing.lg)
            }
            .navigationTitle("Invoice PDF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func generate() async {
        errorMessage = ""
        isGenerating = true
        defer { isGenerating = false }
        do {
            invoice = try await APIService.shared.requestInvoice(
                InvoiceRequest(customerName: order.customerName, orderIds: [order.id])
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

import SwiftUI
import UniformTypeIdentifiers

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
                        NLSelectField(title: "Status", selection: $selectedStatus, value: selectedStatus?.rawValue ?? "All") {
                            Text("All").tag(SigningStatus?.none)
                            ForEach(SigningStatus.allCases) { status in
                                Text(status.rawValue).tag(Optional(status))
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(NLColor.navy)
                    }
                    .nlPanel()

                    NLActionRow {
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
                .nlScreenPadding()
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
            MileageTravelSheet(order: order) { updated in appState.upsertOrder(updated) }
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
        let updated = try await APIService.shared.updateOrderMileage(orderId: order.id, mileage: mileage, travelFee: travelFee)
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
        NLCard(inset: 14) {
            VStack(alignment: .leading, spacing: NLSpacing.md) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(order.customerName)
                            .font(NLFonts.serif(15.5))
                            .foregroundColor(NLColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Signer: \(order.signerName)")
                            .font(NLFonts.sans(12.5))
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
            NLForm {
                NLFormSection("Signing") {
                    DetailRow(label: "Customer", value: liveOrder.customerName)
                    DetailRow(label: "Payer", value: liveOrder.payerName ?? "")
                    DetailRow(label: "Signer", value: liveOrder.signerName)
                    DetailRow(label: "Type", value: liveOrder.signingType ?? "")
                    DetailRow(label: "Date", value: liveOrder.displayDate)
                    DetailRow(label: "Time", value: liveOrder.time ?? "")
                    DetailRow(label: "Status", value: liveOrder.normalizedStatus.rawValue)
                }
                NLFormSection("Payment") {
                    DetailRow(label: "Fee", value: liveOrder.fee.currencyString)
                    DetailRow(label: "Notarial Act Fee", value: liveOrder.notarialActFee.currencyString)
                    DetailRow(label: "Paid", value: liveOrder.paid ? "Yes" : "No")
                    DetailRow(label: "Paid Date", value: liveOrder.paidDate ?? "")
                    DetailRow(label: "Invoice", value: liveOrder.invoiceNumber)
                }
                NLFormSection("Travel") {
                    DetailRow(label: "Mileage", value: liveOrder.mileage.map { String(format: "%.1f mi", $0) } ?? "")
                    DetailRow(label: "Parking and tolls", value: liveOrder.travelFee?.currencyString ?? "")
                }
                NLFormSection("Expenses") { NavigationLink("Signing Expenses") { OrderExpensesView(order: liveOrder) } }
                NLFormSection("Notes") {
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
    var extracted: ExtractedSigning? = nil

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
    @State private var fieldErrors: [String: String] = [:]
    @State private var validationAttempt = UUID()
    @State private var isSaving = false

    var body: some View {
        ScrollViewReader { proxy in
            ZStack {
                ParchmentBackground()
                NLForm {
                    if !errorMessage.isEmpty {
                        NLFormSection { ErrorBanner(message: errorMessage) }
                            .id("orderSaveError")
                    }
                    NLFormSection("Parties") {
                        field("customerName") { NLTextField(title: "Customer name", text: validated($customerName, field: "customerName")) }
                        field("payerName") { NLTextField(title: "Payer name", text: validated($payerName, field: "payerName")) }
                        field("signerName") { NLTextField(title: "Signer name", text: validated($signerName, field: "signerName")) }
                        field("signingType") {
                            NLSelectField(title: "Signing type", selection: validated($signingType, field: "signingType"), value: signingType.isEmpty ? "Select type" : signingType) {
                                Text("Select type").tag("")
                                ForEach(["Loan Signing", "Refinance", "HELOC", "Seller Package", "General Notary", "Other"], id: \.self) { Text($0).tag($0) }
                            }
                        }
                    }
                    NLFormSection("Schedule") {
                        field("date") { NLDateField(title: "Date", selection: validated($date, field: "date")) }
                        field("time") { NLTimeField(title: "Time", time: validated($time, field: "time")) }
                        field("status") {
                            NLSelectField(title: "Status", selection: validated($status, field: "status"), value: status.rawValue) {
                                ForEach(SigningStatus.allCases) { status in
                                    Text(status.rawValue).tag(status)
                                }
                            }
                        }
                    }
                    NLFormSection("Payment") {
                        field("fee") { NLTextField(title: "Fee", text: validated($fee, field: "fee"), keyboardType: .decimalPad) }
                        field("notarialActFee") { NLTextField(title: "Notarial act fee", text: validated($notarialActFee, field: "notarialActFee"), keyboardType: .decimalPad) }
                        field("paid") {
                            Toggle("Paid", isOn: validated($paid, field: "paid"))
                                .disabled(status == .cancelled)
                        }
                        field("paidDate") {
                            Toggle("Has paid date", isOn: validated($hasPaidDate, field: "paidDate"))
                                .disabled(status == .cancelled || !paid)
                            if hasPaidDate && paid && status != .cancelled {
                                NLDateField(title: "Paid date", selection: validated($paidDate, field: "paidDate"))
                            }
                        }
                        field("invoiceNumber") { NLTextField(title: "Invoice number", text: validated($invoiceNumber, field: "invoiceNumber")) }
                    }
                    NLFormSection("Travel") {
                        field("mileage") { NLTextField(title: "Mileage", text: validated($mileage, field: "mileage"), keyboardType: .decimalPad) }
                        field("travelFee") { NLTextField(title: "Parking and tolls", text: validated($travelFee, field: "travelFee"), keyboardType: .decimalPad) }
                    }
                    NLFormSection("Notes") {
                        field("notes") {
                            NLTextArea(title: "Notes", text: validated($notes, field: "notes"), showsLabel: false, minimumHeight: 90)
                        }
                    }
                }
                .disabled(isSaving)
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
            .onChange(of: paid) { _, value in
                fieldErrors["paid"] = nil
                if value && status != .cancelled { status = .paid }
                else if !value && status == .paid { status = .pending; hasPaidDate = false }
            }
            .onChange(of: status) { _, newValue in
                fieldErrors["status"] = nil
                fieldErrors["paid"] = nil
                fieldErrors["paidDate"] = nil
                if newValue == .cancelled {
                    paid = false
                    hasPaidDate = false
                } else if newValue == .paid {
                    paid = true
                    hasPaidDate = true
                } else {
                    paid = false
                    hasPaidDate = false
                }
            }
            .onChange(of: validationAttempt) { _, _ in
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                let target = OrderFormValidation.fieldOrder.first { fieldErrors[$0] != nil } ?? "orderSaveError"
                withAnimation { proxy.scrollTo(target, anchor: .top) }
            }
        }
    }

    private var notarialFeeError: String? {
        if let total = OrderFormValidation.nonnegativeNumber(fee),
           let notarial = OrderFormValidation.nonnegativeNumber(notarialActFee), notarial > total {
            return "Notarial act fee cannot exceed the total fee."
        }
        return fieldErrors["notarialActFee"]
    }

    private func field<Content: View>(_ key: String, @ViewBuilder content: () -> Content) -> some View {
        let error = key == "notarialActFee" ? notarialFeeError : fieldErrors[key]
        return VStack(alignment: .leading, spacing: 6) {
            content().accessibilityHint(error ?? "")
            if let error {
                Text(error)
                    .font(NLTypography.caption)
                    .foregroundStyle(NLColor.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("order-error-\(key)")
            }
        }
        .id(key)
    }

    private func validated<Value>(_ binding: Binding<Value>, field: String) -> Binding<Value> {
        Binding(get: { binding.wrappedValue }, set: { value in
            binding.wrappedValue = value
            fieldErrors[field] = nil
            if field == "fee", ["Notarial act fee cannot exceed the total fee.", "notarialActFee must not exceed fee."].contains(fieldErrors["notarialActFee"] ?? "") {
                fieldErrors["notarialActFee"] = nil
            }
            errorMessage = ""
        })
    }

    private func populate() {
        if let extracted {
            customerName = extracted.customerName ?? ""
            payerName = extracted.payerName ?? extracted.customerName ?? ""
            signerName = extracted.signerName ?? ""
            signingType = extracted.signingType ?? ""
            date = DateParser.date(from: extracted.date) ?? Date()
            time = TimeParser.normalized(extracted.time)
            fee = extracted.fee.map { String($0) } ?? ""
            notarialActFee = "0"
            invoiceNumber = extracted.invoiceNumber ?? ""
            notes = extracted.notes ?? ""
            status = .pending
            return
        }
        guard let order else { return }
        customerName = order.customerName
        payerName = order.payerName ?? ""
        signerName = order.signerName
        signingType = order.signingType ?? ""
        date = DateParser.date(from: order.date) ?? Date()
        time = TimeParser.normalized(order.time)
        fee = String(format: "%.2f", order.fee)
        notarialActFee = String(format: "%.2f", order.notarialActFee)
        paid = order.paid
        if let paidDateValue = DateParser.date(from: order.paidDate) {
            paidDate = paidDateValue
            hasPaidDate = true
        }
        invoiceNumber = order.invoiceNumber
        notes = order.notes ?? ""
        mileage = order.mileage.map { String(format: "%.2f", $0) } ?? ""
        travelFee = order.travelFee.map { String(format: "%.2f", $0) } ?? ""
        status = order.normalizedStatus
    }

    private func save() async {
        guard !isSaving else { return }
        errorMessage = ""
        fieldErrors = OrderFormValidation.errors(customerName: customerName, signerName: signerName, fee: fee,
                                                notarialActFee: notarialActFee, invoiceNumber: invoiceNumber,
                                                notes: notes, time: time, mileage: mileage, travelFee: travelFee)
        guard fieldErrors.isEmpty else { validationAttempt = UUID(); return }
        guard let feeValue = OrderFormValidation.nonnegativeNumber(fee),
              let notarialValue = OrderFormValidation.nonnegativeNumber(notarialActFee.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "0" : notarialActFee) else { return }
        let mileageValue = optionalDouble(mileage)
        let travelValue = optionalDouble(travelFee)

        var payload = SigningOrderPayload(
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

        if let order { payload.preserveMileage = mileageValue == order.mileage && travelValue == order.travelFee }
        isSaving = true
        defer { isSaving = false }
        do {
            try await onSave(payload)
            dismiss()
        } catch let error as OrderValidationFailure {
            fieldErrors = error.fieldErrors
            errorMessage = error.message
            validationAttempt = UUID()
        } catch {
            errorMessage = error.localizedDescription
            validationAttempt = UUID()
        }
    }

    private func optionalDouble(_ value: String) -> Double? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return nil
        }
        guard let number = Double(trimmed), number.isFinite, number >= 0 else { return nil }
        return number
    }

    private func nilIfBlank(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct ImportSigningsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @State private var showImporter = false
    @State private var spreadsheet: SpreadsheetDraft?
    @State private var message = ""
    @State private var draft: ExtractedSigning?
    @State private var error = ""
    @State private var busy = false
    var body: some View {
        NavigationStack {
            ZStack {
                ParchmentBackground()
                VStack(alignment: .leading, spacing: NLSpacing.lg) {
                    ScreenTitleBlock(title: "Import Signings", subtitle: "Upload a screenshot, PDF, or spreadsheet export, then review and edit before saving.")
                    ErrorBanner(message: error)
                    BannerView(kind: .success, message: message)
                    BannerView(kind: .info, message: "Images and PDFs up to 10 MB; CSV, TSV, and TXT exports up to 5 MB. Export Apple Numbers files as CSV. Your account’s plan limits apply.")
                    Button(busy ? "Extracting..." : "Choose Signing File") { showImporter = true }.buttonStyle(PrimaryButtonStyle()).disabled(busy)
                    if busy { ProgressView() }
                    Spacer()
                }.nlScreenPadding()
            }
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() }.disabled(busy) } }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.jpeg, .png, .webP, .pdf, .commaSeparatedText, .tabSeparatedText, .plainText]) { result in
                switch result {
                case .success(let url): Task { await extract(url) }
                case .failure(let failure): error = failure.localizedDescription
                }
            }
            .sheet(item: $spreadsheet) { draft in
                SpreadsheetImportReviewView(draft: draft) { result in
                    result.orders.forEach { appState.upsertOrder($0) }
                    message = "Imported \(result.importedCount) signing(s). Skipped \(result.skippedDuplicateCount) duplicate(s)."
                }
            }
            .sheet(item: $draft) { extracted in
                NavigationStack {
                    SigningOrderFormView(order: nil, onSave: { payload in
                        let order = try await APIService.shared.createOrder(payload)
                        appState.upsertOrder(order)
                        dismiss()
                    }, extracted: extracted)
                }
            }
        }.presentationDetents([.large])
    }
    private func extract(_ url: URL) async {
        error = ""; message = ""; busy = true
        defer { busy = false }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 10 * 1024 * 1024 else { throw APIError.serverError("Choose a file of 10 MB or smaller.") }
            let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? ""
            let data = try Data(contentsOf: url)
            if ["csv", "tsv", "txt"].contains(url.pathExtension.lowercased()) {
                guard !data.isEmpty, data.count <= 5 * 1024 * 1024, let text = String(data: data, encoding: .utf8) else { throw APIError.serverError("Choose a UTF-8 spreadsheet export of 5 MB or smaller.") }
                spreadsheet = SpreadsheetDraft(filename: url.lastPathComponent, mimeType: mime.isEmpty ? "text/plain" : mime, text: text)
                return
            }
            draft = try await APIService.shared.extractSigning(MultipartFile(fieldName: "file", fileName: url.lastPathComponent, mimeType: mime, data: data))
        } catch { self.error = error.localizedDescription }
    }
}

struct MileageTravelSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    let order: SigningOrder
    let onSave: (SigningOrder) -> Void
    @State private var miles = ""
    @State private var parking = ""
    @State private var start = ""
    @State private var destination = ""
    @State private var tripType = "ONE_WAY"
    @State private var mode = "MANUAL"
    @State private var error = ""
    @State private var busy = false
    @State private var calculatedFor = ""
    @State private var clearing = false
    @State private var showClear = false
    private var addressKey: String { start.trimmingCharacters(in: .whitespacesAndNewlines) + "|" + destination.trimmingCharacters(in: .whitespacesAndNewlines) }
    var body: some View {
        NavigationStack {
            ZStack {
                ParchmentBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: NLSpacing.lg) {
                        ScreenTitleBlock(title: "Mileage & Travel", subtitle: order.customerName)
                        ErrorBanner(message: error)
                        NLCard {
                            VStack(spacing: NLSpacing.md) {
                                NLTextField(title: "Start address", text: $start)
                                NLTextField(title: "Destination address", text: $destination)
                                Picker("Entry mode", selection: $mode) { Text("Manual").tag("MANUAL"); Text("Calculated").tag("CALCULATED") }.pickerStyle(.segmented)
                                Picker("Trip", selection: $tripType) { Text("One way").tag("ONE_WAY"); Text("Round trip").tag("ROUND_TRIP") }.pickerStyle(.segmented)
                                if mode == "CALCULATED" {
                                    Button("Calculate Driving Distance") { Task { await calculate() } }.buttonStyle(SecondaryButtonStyle()).disabled(busy || start.isEmpty || destination.isEmpty)
                                }
                                NLTextField(title: "One-way miles", text: $miles, keyboardType: .decimalPad).disabled(mode == "CALCULATED")
                                if let value = Double(miles) { DetailRow(label: "Business miles", value: String(format: "%.2f", (value * 100).rounded() / 100 * (tripType == "ROUND_TRIP" ? 2 : 1))) }
                                NLTextField(title: "Parking and tolls", text: $parking, keyboardType: .decimalPad)
                                Button("Clear Mileage & Travel", role: .destructive) { showClear = true }
                                if clearing { Text("Mileage and travel data will be cleared when you save.").font(NLTypography.caption) }
                            }
                        }
                        if busy { ProgressView() }
                    }.nlScreenPadding()
                }
            }
            .navigationTitle("Travel").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() }.disabled(busy) }
                ToolbarItem(placement: .topBarTrailing) { Button("Save") { Task { await save() } }.disabled(busy) }
            }
        }
        .onChange(of: miles) { _, value in if !value.isEmpty { clearing = false } }
        .onChange(of: parking) { _, value in if !value.isEmpty { clearing = false } }
        .onChange(of: start) { _, value in if !value.isEmpty { clearing = false } }
        .onChange(of: destination) { _, value in if !value.isEmpty { clearing = false } }
        .confirmationDialog("Clear mileage, addresses, and parking?", isPresented: $showClear) {
            Button("Clear Mileage & Travel", role: .destructive) { clearing = true; miles = ""; parking = ""; start = ""; destination = ""; mode = "MANUAL" }
        }
        .onAppear {
            let detail = order.mileageDetails
            tripType = detail?.tripType == "round-trip" ? "ROUND_TRIP" : "ONE_WAY"
            mode = detail?.entryMode ?? "MANUAL"
            miles = detail?.oneWayMiles.map { String($0) } ?? order.mileage.map { String($0 / (tripType == "ROUND_TRIP" ? 2 : 1)) } ?? ""
            parking = order.travelFee.map { String($0) } ?? ""
            start = detail?.tripStartAddress ?? appState.currentUser?.defaultStartAddress ?? ""
            destination = detail?.tripEndAddress ?? ""
            if mode == "CALCULATED" { calculatedFor = addressKey }
        }
    }
    private func calculate() async {
        error = ""; busy = true
        defer { busy = false }
        let key = addressKey
        do {
            let distance = try await APIService.shared.drivingDistance(start: start, destination: destination)
            guard addressKey == key else { error = "Addresses changed. Calculate the distance again."; return }
            miles = String(distance.oneWayMiles); calculatedFor = key; clearing = false
        } catch { self.error = error.localizedDescription }
    }
    private func save() async {
        error = ""
        var object: [String: Any]
        if clearing {
            object = Dictionary(uniqueKeysWithValues: ["miles", "oneWayMiles", "mileageTripType", "mileageEntryMode", "parkingFee", "tripStartAddress", "tripEndAddress"].map { ($0, NSNull()) })
        } else {
            guard miles.isEmpty || (Double(miles).map { $0.isFinite && $0 >= 0 && $0 <= 10000 / (tripType == "ROUND_TRIP" ? 2 : 1) } == true),
                  parking.isEmpty || (Double(parking).map { $0.isFinite && $0 >= 0 && $0 <= 100000 } == true) else { error = "Enter valid, nonnegative mileage and parking values."; return }
            guard mode != "CALCULATED" || (calculatedFor == addressKey && !miles.isEmpty) else { error = "Calculate the distance for the current addresses before saving."; return }
            object = ["oneWayMiles": Double(miles) as Any? ?? NSNull(), "mileageTripType": tripType, "mileageEntryMode": mode,
                      "parkingFee": Double(parking) as Any? ?? NSNull(), "tripStartAddress": start.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty as Any? ?? NSNull(),
                      "tripEndAddress": destination.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty as Any? ?? NSNull()]
        }
        busy = true
        defer { busy = false }
        do {
            let updated = try await APIService.shared.saveMileage(orderId: order.id, payload: JSONSerialization.data(withJSONObject: object))
            onSave(updated); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct GenerateInvoiceSheet: View {
    @Environment(\.dismiss) private var dismiss
    let order: SigningOrder
    @EnvironmentObject private var appState: AppState
    @State private var exportItem: ShareURL?
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

                    Button(isGenerating ? "Generating..." : "Generate Invoice PDF") {
                        Task { await generate() }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(isGenerating)

                    Spacer()
                }
                .nlScreenPadding()
            }
            .navigationTitle("Invoice PDF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .sheet(item: $exportItem) { ShareSheet(activityItems: [$0.url]) }
        .presentationDetents([.medium, .large])
    }

    private func generate() async {
        errorMessage = ""
        isGenerating = true
        defer { isGenerating = false }
        do {
            let billing = try await APIService.shared.fetchBillingStatus()
            guard billing.features?["invoiceGeneration"] == true else { throw APIError.serverError("Upgrade to Pro to generate invoices.") }
            exportItem = ShareURL(url: try LedgerPDF.invoice(user: appState.currentUser, customer: order.customerName, orders: [order]))
        } catch { errorMessage = error.localizedDescription }
    }
}

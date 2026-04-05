import SwiftUI
import Foundation

struct ContentView: View {
    var body: some View {
        NavigationStack {
            LoginView()
        }
    }
}

// MARK: - Model

struct SigningOrder: Identifiable, Equatable {
    let id: UUID
    var customerName: String
    var signerName: String
    var date: Date
    var fee: Double
    var paid: Bool
    var invoiceNumber: String

    init(
        id: UUID = UUID(),
        customerName: String,
        signerName: String,
        date: Date,
        fee: Double,
        paid: Bool,
        invoiceNumber: String
    ) {
        self.id = id
        self.customerName = customerName
        self.signerName = signerName
        self.date = date
        self.fee = fee
        self.paid = paid
        self.invoiceNumber = invoiceNumber
    }
}

// MARK: - Login

struct LoginView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var goToDashboard = false
    @State private var errorMessage = ""

    var body: some View {
        VStack {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 58))
                    .foregroundColor(.blue)

                Text("Notary Signing App")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Log in to manage signing orders")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            .padding(.bottom, 28)

            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Email")
                        .font(.headline)

                    TextField("Enter your email", text: $email)
                        .padding()
                        .background(Color.gray.opacity(0.12))
                        .cornerRadius(12)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Password")
                        .font(.headline)

                    HStack {
                        Group {
                            if showPassword {
                                TextField("Enter your password", text: $password)
                            } else {
                                SecureField("Enter your password", text: $password)
                            }
                        }

                        Button {
                            showPassword.toggle()
                        } label: {
                            Image(systemName: showPassword ? "eye.slash" : "eye")
                                .foregroundColor(.gray)
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.12))
                    .cornerRadius(12)
                }

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.footnote)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    login()
                } label: {
                    Text("Log In")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }

                HStack(spacing: 4) {
                    Text("Don’t have an account?")
                        .foregroundColor(.gray)

                    NavigationLink("Sign Up") {
                        SignUpView()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
                }
                .font(.subheadline)
                .padding(.top, 4)
            }
            .padding()
            .background(Color.white.opacity(0.96))
            .cornerRadius(20)
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
            .padding(.horizontal)

            Spacer()
        }
        .padding()
        .background(
            LinearGradient(
                colors: [Color.blue.opacity(0.15), Color.white],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .navigationDestination(isPresented: $goToDashboard) {
            DashboardView()
        }
    }

    private func login() {
        errorMessage = ""

        if email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = "Please enter your email."
            return
        }

        if password.isEmpty {
            errorMessage = "Please enter your password."
            return
        }

        goToDashboard = true
    }
}

// MARK: - Sign Up

struct SignUpView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var fullName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showPassword = false
    @State private var showConfirmPassword = false
    @State private var goToDashboard = false
    @State private var errorMessage = ""

    var body: some View {
        VStack {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 58))
                    .foregroundColor(.blue)

                Text("Create Account")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Sign up to manage signing orders")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            .padding(.bottom, 28)

            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Full Name")
                        .font(.headline)

                    TextField("Enter your full name", text: $fullName)
                        .padding()
                        .background(Color.gray.opacity(0.12))
                        .cornerRadius(12)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Email")
                        .font(.headline)

                    TextField("Enter your email", text: $email)
                        .padding()
                        .background(Color.gray.opacity(0.12))
                        .cornerRadius(12)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Password")
                        .font(.headline)

                    HStack {
                        Group {
                            if showPassword {
                                TextField("Create a password", text: $password)
                            } else {
                                SecureField("Create a password", text: $password)
                            }
                        }

                        Button {
                            showPassword.toggle()
                        } label: {
                            Image(systemName: showPassword ? "eye.slash" : "eye")
                                .foregroundColor(.gray)
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.12))
                    .cornerRadius(12)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Confirm Password")
                        .font(.headline)

                    HStack {
                        Group {
                            if showConfirmPassword {
                                TextField("Confirm your password", text: $confirmPassword)
                            } else {
                                SecureField("Confirm your password", text: $confirmPassword)
                            }
                        }

                        Button {
                            showConfirmPassword.toggle()
                        } label: {
                            Image(systemName: showConfirmPassword ? "eye.slash" : "eye")
                                .foregroundColor(.gray)
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.12))
                    .cornerRadius(12)
                }

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.footnote)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    signUp()
                } label: {
                    Text("Create Account")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }

                Button("Back to Login") {
                    dismiss()
                }
                .font(.subheadline)
                .foregroundColor(.blue)
            }
            .padding()
            .background(Color.white.opacity(0.96))
            .cornerRadius(20)
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
            .padding(.horizontal)

            Spacer()
        }
        .padding()
        .background(
            LinearGradient(
                colors: [Color.blue.opacity(0.15), Color.white],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .navigationTitle("Sign Up")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $goToDashboard) {
            DashboardView()
        }
    }

    private func signUp() {
        errorMessage = ""

        if fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = "Please enter your full name."
            return
        }

        if email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = "Please enter your email."
            return
        }

        if !email.contains("@") || !email.contains(".") {
            errorMessage = "Please enter a valid email address."
            return
        }

        if password.isEmpty {
            errorMessage = "Please enter a password."
            return
        }

        if password.count < 6 {
            errorMessage = "Password must be at least 6 characters."
            return
        }

        if confirmPassword != password {
            errorMessage = "Passwords do not match."
            return
        }

        goToDashboard = true
    }
}

// MARK: - Dashboard

struct DashboardView: View {
    @State private var signingOrders: [SigningOrder] = [
        SigningOrder(
            customerName: "First Escrow",
            signerName: "Michael Torres",
            date: Date(),
            fee: 150.00,
            paid: false,
            invoiceNumber: "INV-1001"
        ),
        SigningOrder(
            customerName: "Prime Title",
            signerName: "Sarah Johnson",
            date: Date().addingTimeInterval(86400),
            fee: 175.00,
            paid: true,
            invoiceNumber: "INV-1002"
        )
    ]

    @State private var showAddOrder = false

    var body: some View {
        VStack {
            if signingOrders.isEmpty {
                ContentUnavailableView(
                    "No Signing Orders",
                    systemImage: "tray",
                    description: Text("Tap Add to create your first signing order.")
                )
            } else {
                List {
                    ForEach($signingOrders) { $order in
                        NavigationLink {
                            SigningOrderDetailView(order: $order)
                        } label: {
                            SigningOrderRow(order: order)
                        }
                    }
                    .onDelete(perform: deleteOrder)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Dashboard")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddOrder = true
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddOrder) {
            AddSigningOrderView { newOrder in
                signingOrders.append(newOrder)
            }
        }
    }

    private func deleteOrder(at offsets: IndexSet) {
        signingOrders.remove(atOffsets: offsets)
    }
}

// MARK: - Row

struct SigningOrderRow: View {
    let order: SigningOrder

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(order.customerName)
                    .font(.headline)

                Spacer()

                Text(order.paid ? "Paid" : "Unpaid")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background((order.paid ? Color.green : Color.orange).opacity(0.15))
                    .foregroundColor(order.paid ? .green : .orange)
                    .cornerRadius(10)
            }

            Text("Signer: \(order.signerName)")
                .font(.subheadline)
                .foregroundColor(.gray)

            Text("Invoice: \(order.invoiceNumber)")
                .font(.subheadline)
                .foregroundColor(.gray)

            HStack {
                Text(order.date.formatted(date: .abbreviated, time: .omitted))
                Spacer()
                Text("$" + String(format: "%.2f", order.fee))
                    .fontWeight(.semibold)
            }
            .font(.subheadline)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Details Screen

struct SigningOrderDetailView: View {
    @Binding var order: SigningOrder
    @State private var showEditScreen = false

    var body: some View {
        Form {
            Section("Signing Details") {
                DetailRow(label: "Customer Name", value: order.customerName)
                DetailRow(label: "Signer Name", value: order.signerName)
                DetailRow(label: "Date", value: order.date.formatted(date: .abbreviated, time: .omitted))
                DetailRow(label: "Fee", value: "$" + String(format: "%.2f", order.fee))
                DetailRow(label: "Paid", value: order.paid ? "Yes" : "No")
                DetailRow(label: "Invoice No", value: order.invoiceNumber)
            }
        }
        .navigationTitle("Order Details")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") {
                    showEditScreen = true
                }
            }
        }
        .sheet(isPresented: $showEditScreen) {
            NavigationStack {
                EditSigningOrderView(order: $order)
            }
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundColor(.gray)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Edit Screen

struct EditSigningOrderView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var order: SigningOrder

    @State private var customerName: String = ""
    @State private var signerName: String = ""
    @State private var date: Date = Date()
    @State private var fee: String = ""
    @State private var paid: Bool = false
    @State private var invoiceNumber: String = ""
    @State private var errorMessage = ""

    var body: some View {
        Form {
            Section("Edit Signing Details") {
                TextField("Customer name", text: $customerName)
                TextField("Signer name", text: $signerName)
                DatePicker("Date", selection: $date, displayedComponents: .date)
                TextField("Fee", text: $fee)
                    .keyboardType(.decimalPad)
                Toggle("Paid", isOn: $paid)
                TextField("Invoice No", text: $invoiceNumber)
            }

            if !errorMessage.isEmpty {
                Section {
                    Text(errorMessage)
                        .foregroundColor(.red)
                }
            }
        }
        .navigationTitle("Edit Order")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    saveChanges()
                }
            }
        }
        .onAppear {
            customerName = order.customerName
            signerName = order.signerName
            date = order.date
            fee = String(format: "%.2f", order.fee)
            paid = order.paid
            invoiceNumber = order.invoiceNumber
        }
    }

    private func saveChanges() {
        errorMessage = ""

        if customerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = "Please enter customer name."
            return
        }

        if signerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = "Please enter signer name."
            return
        }

        if invoiceNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = "Please enter invoice number."
            return
        }

        guard let feeValue = Double(fee), feeValue >= 0 else {
            errorMessage = "Please enter a valid fee."
            return
        }

        order.customerName = customerName
        order.signerName = signerName
        order.date = date
        order.fee = feeValue
        order.paid = paid
        order.invoiceNumber = invoiceNumber

        dismiss()
    }
}

// MARK: - Add Screen

struct AddSigningOrderView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var customerName = ""
    @State private var signerName = ""
    @State private var date = Date()
    @State private var fee = ""
    @State private var paid = false
    @State private var invoiceNumber = ""
    @State private var errorMessage = ""

    let onSave: (SigningOrder) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Signing Details") {
                    TextField("Customer name", text: $customerName)
                    TextField("Signer name", text: $signerName)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField("Fee", text: $fee)
                        .keyboardType(.decimalPad)
                    Toggle("Paid", isOn: $paid)
                    TextField("Invoice No", text: $invoiceNumber)
                }

                if !errorMessage.isEmpty {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("New Signing Order")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        saveOrder()
                    }
                }
            }
        }
    }

    private func saveOrder() {
        errorMessage = ""

        if customerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = "Please enter customer name."
            return
        }

        if signerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = "Please enter signer name."
            return
        }

        if invoiceNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = "Please enter invoice number."
            return
        }

        guard let feeValue = Double(fee), feeValue >= 0 else {
            errorMessage = "Please enter a valid fee."
            return
        }

        let newOrder = SigningOrder(
            customerName: customerName,
            signerName: signerName,
            date: date,
            fee: feeValue,
            paid: paid,
            invoiceNumber: invoiceNumber
        )

        onSave(newOrder)
        dismiss()
    }
}

#Preview {
    ContentView()
}

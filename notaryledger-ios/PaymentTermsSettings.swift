import SwiftUI

struct SigningPaymentDefaults {
    var defaults: UserDefaults = .standard
    static let allowedDays = 0...365

    func days(for ownerID: String) -> Int? {
        guard let value = defaults.object(forKey: key(ownerID)) as? Int,
            Self.allowedDays.contains(value)
        else { return nil }
        return value
    }

    func save(days: Int?, for ownerID: String) {
        guard !ownerID.isEmpty else { return }
        if let days, Self.allowedDays.contains(days) {
            defaults.set(days, forKey: key(ownerID))
        } else {
            defaults.removeObject(forKey: key(ownerID))
        }
    }

    static func parse(_ text: String) -> Int? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.allSatisfy(\.isNumber), let days = Int(value), allowedDays.contains(days) else { return nil }
        return days
    }

    func applying(to order: SigningOrderPayload, ownerID: String?) -> SigningOrderPayload {
        guard let ownerID, let days = days(for: ownerID), order.dueDate == .unchanged else { return order }
        let timestamp = SigningOrderPayload.scheduledDate(date: order.date, time: order.time)
        guard let signingDay = OrderPaymentRules.signingDay(timestamp), let day = OrderCalendarDay(signingDay) else { return order }
        var result = order
        result.dueDate = .set(day.adding(days: days).key)
        return result
    }

    func applying(to imported: SigningOrder, ownerID: String?) -> SigningOrderPayload? {
        guard imported.dueDate == nil else { return nil }
        let clock = TimeParser.normalized(imported.time)
        var payload = SigningOrderPayload(
            customerName: imported.customerName, payerName: imported.payerName,
            signerName: imported.signerName, signingType: imported.signingType, date: imported.date,
            time: imported.date.contains("T") || clock.isEmpty ? nil : clock,
            fee: imported.fee, notarialActFee: imported.notarialActFee, paid: imported.isCollected,
            paidDate: imported.paidDate, invoiceNumber: imported.invoiceNumber, notes: imported.notes,
            mileage: nil, travelFee: nil, status: imported.normalizedStatus)
        payload.preserveMileage = true
        let prepared = applying(to: payload, ownerID: ownerID)
        return prepared.dueDate == .unchanged ? nil : prepared
    }

    private func key(_ ownerID: String) -> String { "notary_default_payment_due_days_v1.\(ownerID)" }
}

struct PaymentTermsSettingsView: View {
    let ownerID: String
    @State private var days = ""
    @State private var error = ""
    @State private var success = ""

    var body: some View {
        NLCard {
            VStack(alignment: .leading, spacing: NLSpacing.md) {
                Text("Payment terms").font(NLTypography.cardTitle).foregroundStyle(NLColor.navy)
                NLTextField(title: "Default payment due (days)", text: $days, keyboardType: .numberPad)
                Text(
                    "Set once for new signings. For example, 30 means payment is due 30 days after the signing date. Use 0 for the same day, or leave blank for no default."
                )
                .font(NLTypography.caption).foregroundStyle(NLColor.muted)
                Text("Saved for your account on this device. Existing signing due dates stay unchanged.")
                    .font(NLTypography.caption).foregroundStyle(NLColor.muted)
                ErrorBanner(message: error)
                BannerView(kind: .success, message: success)
                Button("Save Payment Terms") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    error = ""
                    success = ""
                    let value = days.trimmingCharacters(in: .whitespacesAndNewlines)
                    let parsed = SigningPaymentDefaults.parse(value)
                    guard value.isEmpty || parsed != nil else {
                        error = "Enter a whole number from 0 to 365, or leave blank for no default."
                        return
                    }
                    SigningPaymentDefaults().save(days: parsed, for: ownerID)
                    days = parsed.map(String.init) ?? ""
                    success = "Default payment terms saved."
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .task(id: ownerID) {
            days = SigningPaymentDefaults().days(for: ownerID).map(String.init) ?? ""
            error = ""
            success = ""
        }
    }
}

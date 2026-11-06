import Foundation

nonisolated enum OrderFormValidation {
    static let fieldOrder = ["customerName", "payerName", "signerName", "signingType", "date", "time", "status", "fee", "notarialActFee", "paid", "paidDate", "invoiceNumber", "mileage", "travelFee", "notes"]

    static func errors(customerName: String, signerName: String, fee: String, notarialActFee: String,
                       invoiceNumber: String, notes: String, time: String, mileage: String, travelFee: String) -> [String: String] {
        var errors: [String: String] = [:]
        if customerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { errors["customerName"] = "Please enter customer name." }
        if signerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { errors["signerName"] = "Please enter signer name." }
        let feeValue = nonnegativeNumber(fee)
        if feeValue == nil { errors["fee"] = "Please enter a valid fee." }
        let notarialValue = nonnegativeNumber(notarialActFee.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "0" : notarialActFee)
        if notarialValue == nil { errors["notarialActFee"] = "Please enter a valid notarial act fee." }
        else if let feeValue, let notarialValue, notarialValue > feeValue {
            errors["notarialActFee"] = "Notarial act fee cannot exceed the total fee."
        }
        if invoiceNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { errors["invoiceNumber"] = "Please enter invoice number." }
        if notes.utf16.count > 255 { errors["notes"] = "Notes must be 255 characters or fewer." }
        if !time.isEmpty, time.range(of: #"^([01][0-9]|2[0-3]):[0-5][0-9]$"#, options: .regularExpression) == nil {
            errors["time"] = "Enter time as HH:mm (24-hour)."
        }
        if !mileage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, nonnegativeNumber(mileage) == nil {
            errors["mileage"] = "Enter valid mileage."
        }
        if !travelFee.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, nonnegativeNumber(travelFee) == nil {
            errors["travelFee"] = "Enter valid parking and tolls."
        }
        return errors
    }

    static func nonnegativeNumber(_ value: String) -> Double? {
        guard let number = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)), number.isFinite, number >= 0 else { return nil }
        return number
    }

    static func fieldName(_ apiField: String) -> String {
        let field = apiField.hasPrefix("mileage.") ? String(apiField.dropFirst("mileage.".count)) : apiField
        switch field {
        case "paymentStatus": return "status"
        case "miles", "businessMiles", "oneWayMiles", "roundTripMiles": return "mileage"
        case "parkingFee": return "travelFee"
        default: return field
        }
    }
}

nonisolated struct OrderValidationFailure: LocalizedError {
    let message: String
    let fieldErrors: [String: String]
    var errorDescription: String? { message }

    static func fromResponse(_ data: Data) -> Self? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let error = object["error"] as? [String: Any] ?? [:]
        let message = error["message"] as? String ?? object["message"] as? String ?? "Please review the highlighted fields."
        // Same candidate precedence and field shapes as the web API helper.
        let candidates = [error["fieldErrors"], error["fields"], object["fieldErrors"], object["fields"], object["errors"], error["details"]]
        var fields: [String: String] = [:]
        for candidate in candidates {
            if let dictionary = candidate as? [String: Any] {
                for (key, value) in dictionary {
                    if let text = (value as? String) ?? (value as? [String])?.first, !text.isEmpty {
                        fields[OrderFormValidation.fieldName(key)] = text
                    }
                }
                break
            }
            if let details = candidate as? [[String: Any]] {
                for detail in details {
                    if let key = detail["field"] as? String ?? detail["path"] as? String ?? detail["name"] as? String,
                       let text = detail["message"] as? String ?? detail["error"] as? String, !text.isEmpty {
                        fields[OrderFormValidation.fieldName(key)] = text
                    }
                }
                break
            }
        }
        // The current orders API also returns field-specific plain messages.
        if fields.isEmpty {
            for field in OrderFormValidation.fieldOrder + ["paymentStatus", "miles", "parkingFee"] {
                if message == "Invalid \(field)." || message.hasPrefix("\(field) is ") || message.hasPrefix("\(field) must ") {
                    fields[OrderFormValidation.fieldName(field)] = message
                    break
                }
            }
        }
        return fields.isEmpty ? nil : Self(message: message, fieldErrors: fields)
    }
}

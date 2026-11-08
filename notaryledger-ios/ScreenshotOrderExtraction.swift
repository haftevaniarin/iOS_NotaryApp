import Foundation

nonisolated enum ScreenshotOrderField: String, CaseIterable, Identifiable, Sendable {
    case reference, company, contactName, contactPhone, contactEmail
    case signer, signerPhone, signerEmail, date, time, location, appointmentType, documentType, fee, instructions

    var id: String { rawValue }
    var title: String {
        switch self {
        case .reference: "Order reference"
        case .company: "Signing or title company"
        case .contactName: "Contact name"
        case .contactPhone: "Contact phone"
        case .contactEmail: "Contact email"
        case .signer: "Signer names"
        case .signerPhone: "Signer phone"
        case .signerEmail: "Signer email"
        case .date: "Signing date"
        case .time: "Signing time"
        case .location: "Signing location"
        case .appointmentType: "Appointment type"
        case .documentType: "Document type"
        case .fee: "Notary fee"
        case .instructions: "Special instructions"
        }
    }

    var aliases: [String] {
        switch self {
        case .reference: ["order number", "order no.", "order no", "order #", "order id", "reference number", "reference", "ref #", "assignment number", "file number"]
        case .company: ["signing company", "title company", "customer name", "company"]
        case .contactName: ["contact name", "contact", "escrow officer", "scheduler"]
        case .contactPhone: ["contact phone", "company phone", "phone", "telephone"]
        case .contactEmail: ["contact email", "company email", "email"]
        case .signer: ["signer names", "signer name", "signers", "signer", "borrower names", "borrower name", "borrowers", "borrower"]
        case .signerPhone: ["signer phone", "borrower phone", "signer telephone"]
        case .signerEmail: ["signer email", "borrower email"]
        case .date: ["signing date & time", "appointment date & time", "signing date and time", "appointment date and time", "date & time", "date and time", "date/time", "date / time", "date&time", "date &time", "signing date", "appointment date", "closing date", "date"]
        case .time: ["signing time", "appointment time", "time"]
        case .location: ["signing location", "signing address", "appointment location", "property address", "location", "address"]
        case .appointmentType: ["appointment type", "signing type", "service type"]
        case .documentType: ["document type", "documents", "loan type"]
        case .fee: ["notary fee", "signing fee", "agreed fee", "notary compensation", "fee"]
        case .instructions: ["special instructions", "signing instructions", "instructions", "notes"]
        }
    }
}

nonisolated struct ScreenshotTextLine: Sendable {
    let text: String
    var confidence: Float = 1
}

nonisolated struct ScreenshotOrderDraft: Sendable {
    var values: [ScreenshotOrderField: String] = [:]
    var warnings: [ScreenshotOrderField: String] = [:]
    var evidence: [ScreenshotOrderField: String] = [:]
    var scheduleExplanation: String?

    subscript(_ field: ScreenshotOrderField) -> String {
        get { values[field] ?? "" }
        set { values[field] = newValue }
    }

    var formFields: ScreenshotOrderFormFields {
        ScreenshotOrderFormFields(customerName: self[.company], signerName: self[.signer], signingType: SigningTypeOptions.matching(self[.appointmentType]) ?? "",
                                  date: self[.date], time: self[.time], fee: self[.fee], notes: mappedNotes)
    }

    // Keep fields without backend equivalents in labeled notes. Never truncate personal details.
    var mappedNotes: String {
        let fields: [ScreenshotOrderField] = [.reference, .contactName, .contactPhone, .contactEmail, .signerPhone, .signerEmail, .location, .documentType, .instructions]
        var lines = fields.compactMap { field in
            let value = self[field].trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : "\(field.title): \(value)"
        }
        if let sourceType = evidence[.appointmentType], sourceType != self[.appointmentType] {
            lines.append("Screenshot signing type: \(sourceType)")
        }
        return lines.joined(separator: "\n")
    }
}

nonisolated struct ScreenshotOrderFormFields: Sendable {
    let customerName: String
    let signerName: String
    let signingType: String
    let date: String
    let time: String
    let fee: String
    let notes: String
    // An order reference is not evidence of an invoice number or who will pay.
    let invoiceNumber = ""
    let payerName = ""
}

nonisolated enum ScreenshotImportError: LocalizedError {
    case unreadable, noDetails, tooLarge, recognitionFailed
    var errorDescription: String? {
        switch self {
        case .unreadable: "This screenshot is unreadable. Choose a clear, full-resolution image with visible text."
        case .noDetails: "No recognizable order details were found. Choose an order confirmation or assignment with labeled details."
        case .tooLarge: "Choose a screenshot of 10 MB or smaller."
        case .recognitionFailed: "Text recognition could not finish. Try again or choose another screenshot."
        }
    }
}

nonisolated enum ScreenshotOrderExtractor {
    private struct Label {
        let field: ScreenshotOrderField
        let value: String
        let genericContact: Bool
        let includesTime: Bool
    }

    private static func label(in text: String) -> Label? {
        // Longest labels first, so "Signer phone" cannot be mistaken for "Signer".
        let aliases = ScreenshotOrderField.allCases.flatMap { field in field.aliases.map { (field, $0) } }
            .sorted { $0.1.count > $1.1.count }
        for (field, alias) in aliases {
            let pattern = "^" + NSRegularExpression.escapedPattern(for: alias) + #"(?:\s*[:：#=–-]\s*|\s+|$)(.*)$"#
            if let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]), range.lowerBound == text.startIndex,
               let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let valueRange = Range(match.range(at: 1), in: text) {
                let value = String(text[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                return Label(field: field, value: ["information", "details", "info"].contains(value.lowercased()) ? "" : value,
                             genericContact: ["phone", "telephone", "email"].contains(alias),
                             includesTime: field == .date && alias.contains("time"))
            }
        }
        return nil
    }

    static func extract(_ input: [ScreenshotTextLine], localTimeZone: TimeZone = .current) throws -> ScreenshotOrderDraft {
        let lines = input.flatMap { line in
            line.text.components(separatedBy: .newlines).flatMap { splitInlineLabels($0) }
                .map { ScreenshotTextLine(text: $0.trimmingCharacters(in: .whitespacesAndNewlines), confidence: line.confidence) }
        }.filter { !$0.text.isEmpty }
        guard !lines.isEmpty else { throw ScreenshotImportError.unreadable }
        var candidates: [ScreenshotOrderField: [ScreenshotTextLine]] = [:]
        var index = 0
        var signerSection = false
        while index < lines.count {
            let line = lines[index]
            guard let found = label(in: line.text) else { index += 1; continue }
            var field = found.field
            if field == .signer { signerSection = true }
            if [.company, .contactName].contains(field) { signerSection = false }
            if signerSection && found.genericContact && field == .contactPhone { field = .signerPhone }
            if signerSection && found.genericContact && field == .contactEmail { field = .signerEmail }
            var value = found.value
            var confidence = line.confidence
            // Also support a label on its own line, and multiline addresses/instructions/signers.
            while index + 1 < lines.count, label(in: lines[index + 1].text) == nil,
                  value.isEmpty || [.location, .instructions, .signer].contains(field)
                    || (field == .date && (found.includesTime || ScreenshotAppointmentParser.parse(value, localTimeZone: localTimeZone) != nil)
                        && (ScreenshotAppointmentParser.isTimeContinuation(lines[index + 1].text) || ScreenshotAppointmentParser.isTimeZoneLine(lines[index + 1].text))) {
                index += 1
                value += (value.isEmpty ? "" : "\n") + lines[index].text
                confidence = min(confidence, lines[index].confidence)
            }
            let unavailable = ["n/a", "na", "none", "not provided", "not available", "unknown", "tbd", "-", "—", "pending"]
            if !value.isEmpty && !unavailable.contains(value.lowercased()) {
                candidates[field, default: []].append(ScreenshotTextLine(text: value, confidence: confidence))
                if field == .date && (found.includesTime || ScreenshotAppointmentParser.parse(value, localTimeZone: localTimeZone) != nil) {
                    candidates[.time, default: []].append(ScreenshotTextLine(text: value, confidence: confidence))
                }
            }
            index += 1
        }
        let orderFields: Set<ScreenshotOrderField> = [.reference, .company, .signer, .date, .time, .location, .appointmentType, .documentType, .fee]
        guard !orderFields.isDisjoint(with: candidates.keys) else { throw ScreenshotImportError.noDetails }
        var draft = ScreenshotOrderDraft()
        for (field, items) in candidates {
            let unique = items.map(\.text).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            draft.evidence[field] = unique.joined(separator: " / ")
            if unique.count > 1 && field != .signer && field != .instructions {
                draft.warnings[field] = "Multiple values found. Enter the correct value from the screenshot."
                continue
            }
            let raw = unique.joined(separator: "\n")
            var value: String? = raw
            let appointment = [.date, .time].contains(field) ? ScreenshotAppointmentParser.parse(raw, localTimeZone: localTimeZone) : nil
            switch field {
            case .date: value = appointment?.date ?? normalizedDate(raw)
            case .time: value = appointment?.time ?? normalizedTime(raw)
            case .fee: value = normalizedFee(raw)
            case .appointmentType: value = SigningTypeOptions.matching(raw)
            case .contactEmail, .signerEmail:
                if raw.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) == nil { value = nil }
            case .contactPhone, .signerPhone:
                let digits = raw.filter(\.isNumber).count
                if digits < 7 || digits > 20 { value = nil }
            default: break
            }
            draft[field] = value ?? ""
            if let explanation = appointment?.reviewMessage { draft.scheduleExplanation = explanation }
            if value == nil {
                draft.warnings[field] = field == .appointmentType
                    ? "Choose the matching signing type from the Notary Ledger options."
                    : appointment?.warning ?? "Ambiguous or unsupported value. Enter and confirm the correct value."
            }
            else if items.contains(where: { $0.confidence < 0.85 }) { draft.warnings[field] = "Text recognition is uncertain. Check this value against the screenshot." }
        }
        return draft
    }

    private static func splitInlineLabels(_ text: String) -> [String] {
        // Two-column cards may place several labeled values on a single OCR baseline.
        if label(in: text.trimmingCharacters(in: .whitespaces))?.field == .instructions { return [text] }
        let aliases = ScreenshotOrderField.allCases.flatMap(\.aliases).sorted { $0.count > $1.count }
            .map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        guard let regex = try? NSRegularExpression(pattern: "(?<!\\S)(?:" + aliases + ")\\s*[:：=]", options: .caseInsensitive) else { return [text] }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard matches.count > 1 else { return [text] }
        let string = text as NSString
        return matches.enumerated().map { index, match in
            let end = index + 1 < matches.count ? matches[index + 1].range.location : string.length
            return string.substring(with: NSRange(location: match.range.location, length: end - match.range.location))
        }
    }

    static func normalizedDate(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var formats = ["yyyy-MM-dd", "MMMM d, yyyy", "MMM d, yyyy", "MMMM d yyyy", "MMM d yyyy"]
        let numeric = trimmed.components(separatedBy: CharacterSet(charactersIn: "/-"))
        if numeric.count == 3, numeric[2].count == 4, let first = Int(numeric[0]), let second = Int(numeric[1]) {
            guard first == second || first > 12 || second > 12 else { return nil }
            formats += first > 12 ? ["d/M/yyyy", "d-M-yyyy", "dd/MM/yyyy", "dd-MM-yyyy"] : ["M/d/yyyy", "M-d-yyyy", "MM/dd/yyyy", "MM-dd-yyyy"]
        }
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            formatter.isLenient = false
            guard let date = formatter.date(from: trimmed), formatter.string(from: date).lowercased() == trimmed.lowercased() else { continue }
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: date)
        }
        return nil
    }

    static func normalizedTime(_ text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if value.range(of: #"^(?:[01]\d|2[0-3]):[0-5]\d$"#, options: .regularExpression) != nil {
            let hour = Int(value.prefix(2)) ?? 0
            return hour == 0 || hour > 12 ? value : nil
        }
        for format in ["h:mm a", "h a", "h:mma", "ha", "hh:mm a", "hh:mma"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            formatter.isLenient = false
            if let date = formatter.date(from: value), formatter.string(from: date) == value {
                formatter.dateFormat = "HH:mm"
                return formatter.string(from: date)
            }
        }
        return nil
    }

    static func normalizedFee(_ text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.range(of: #"^(?:USD\s*|\$\s*)?(?:\d+|\d{1,3}(?:,\d{3})+)(?:\.\d{1,2})?(?:\s+USD)?$"#, options: [.regularExpression, .caseInsensitive]) != nil else { return nil }
        let number = value.uppercased().replacingOccurrences(of: "USD", with: "").replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        guard let fee = Double(number), fee.isFinite, fee >= 0 else { return nil }
        return number
    }
}

enum ScreenshotDuplicateDetection {
    static func matches(notes: String, signer: String, date: String, orders: [SigningOrder]) -> [SigningOrder] {
        matches(reference: noteValue("Order reference", in: notes), signer: signer, date: date,
                location: noteValue("Signing location", in: notes), orders: orders)
    }

    static func matches(reference: String, signer: String, date: String, location: String, orders: [SigningOrder]) -> [SigningOrder] {
        let ref = normalizedReference(reference), name = normalized(signer), address = normalized(location)
        return orders.filter { order in
            let storedReference = noteValue("Order reference", in: order.notes)
            if !ref.isEmpty && (ref == normalizedReference(storedReference) || ref == normalizedReference(order.invoiceNumber)) { return true }
            guard !name.isEmpty, !date.isEmpty, !address.isEmpty else { return false }
            let storedLocation = noteValue("Signing location", in: order.notes)
            let destination = order.mileageDetails?.tripEndAddress ?? ""
            let storedDate = order.date.contains("T") ? DateParser.date(from: order.date).map { DateParser.apiDateString(from: $0) } ?? String(order.date.prefix(10)) : order.date
            return normalized(order.signerName) == name && storedDate == date
                && (normalized(storedLocation) == address || normalized(destination) == address)
        }
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func normalizedReference(_ value: String) -> String {
        normalized(value).replacingOccurrences(of: " ", with: "")
    }

    private static func noteValue(_ label: String, in notes: String?) -> String {
        let prefix = label + ":"
        let lines = notes?.components(separatedBy: .newlines) ?? []
        guard let index = lines.firstIndex(where: { $0.lowercased().hasPrefix(prefix.lowercased()) }) else { return "" }
        var value = String(lines[index].dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        for line in lines.dropFirst(index + 1) {
            if ScreenshotOrderField.allCases.contains(where: { line.hasPrefix($0.title + ":") }) { break }
            value += "\n" + line
        }
        return value
    }
}

nonisolated enum ScreenshotImportValidation {
    static func errors(date: String, time: String, confirmedDate: Bool, confirmedTime: Bool,
                       confirmedFee: Bool, confirmedReview: Bool, requiresTimeConfirmation: Bool = false,
                       signingType: String = "", requiresSigningType: Bool = false) -> [String: String] {
        var errors: [String: String] = [:]
        if date.isEmpty || ScreenshotOrderExtractor.normalizedDate(date) != date {
            errors["date"] = "Enter a valid signing date as YYYY-MM-DD."
        } else if !confirmedDate { errors["date"] = "Confirm the signing date against the screenshot." }
        if (!time.isEmpty || requiresTimeConfirmation) && !confirmedTime { errors["time"] = "Confirm the signing time and local time zone, or confirm leaving it blank." }
        if !confirmedFee { errors["fee"] = "Confirm the notary fee in USD." }
        if !confirmedReview { errors["review"] = "Review the form and agree to save these fields to your account." }
        if (requiresSigningType || !signingType.isEmpty) && !SigningTypeOptions.values.contains(signingType) {
            errors["signingType"] = "Choose a signing type from the Notary Ledger options."
        }
        return errors
    }
}

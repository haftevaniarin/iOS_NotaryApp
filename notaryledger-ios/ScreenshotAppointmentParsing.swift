import Foundation

nonisolated enum ScreenshotAppointmentParser {
    struct Result {
        let date: String?
        let time: String?
        var warning: String? = nil
        var reviewMessage: String? = nil
    }

    /// Parses an explicitly labeled appointment, never dates from the phone's status bar or email header.
    static func parse(_ raw: String, localTimeZone: TimeZone) -> Result? {
        let text = raw.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        let pattern = #"^(.+?)\s+(?:at\s+)?(\d{1,2}(?::\d{2})?(?:\s*(?:AM|PM))?)(?:\s*(\([^()]+\)|[A-Z][A-Z_/:+\d-]*|[+-]\d{2}:?\d{2}))?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let dateRange = Range(match.range(at: 1), in: text),
              let timeRange = Range(match.range(at: 2), in: text) else { return nil }

        let date = ScreenshotOrderExtractor.normalizedDate(String(text[dateRange]))
        let time = ScreenshotOrderExtractor.normalizedTime(String(text[timeRange]))
        guard let zoneRange = Range(match.range(at: 3), in: text) else {
            return Result(date: date, time: time)
        }
        let zoneText = String(text[zoneRange]).trimmingCharacters(in: CharacterSet(charactersIn: "() "))
        guard let zone = sourceTimeZone(zoneText) else {
            return Result(date: nil, time: nil, warning: "Unrecognized or ambiguous time zone. Enter the appointment in your device’s local time and confirm it.")
        }
        guard let date, let time else { return Result(date: nil, time: nil) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = zone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.isLenient = false
        let sourceValue = "\(date) \(time)"
        guard let instant = formatter.date(from: sourceValue), formatter.string(from: instant) == sourceValue else { return Result(date: nil, time: nil) }
        formatter.timeZone = localTimeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let localDate = formatter.string(from: instant)
        formatter.dateFormat = "HH:mm"
        let localTime = formatter.string(from: instant)
        return Result(date: localDate, time: localTime,
                      reviewMessage: "Screenshot appointment: \(text). In your device’s time zone (\(localTimeZone.identifier)): \(localDate) at \(localTime). Review and confirm the date and time.")
    }

    static func isTimeContinuation(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.range(of: #"^(?:at\s+)?\d{1,2}(?::\d{2})?(?:\s*(?:AM|PM))?(?:\s*\([^()]+\))?$"#,
                           options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func isTimeZoneLine(_ text: String) -> Bool {
        text.range(of: #"^\(?\s*(?:[A-Z]{2,5}|(?:UTC|GMT)?[+-]\d{2}:?\d{2})\s*\)?$"#,
                   options: .regularExpression) != nil
    }

    private static func sourceTimeZone(_ text: String) -> TimeZone? {
        // Fixed offsets preserve the abbreviation printed in the screenshot, even in a different season.
        // Ambiguous abbreviations such as CST and IST intentionally require manual review.
        let offsets = ["UTC": 0, "GMT": 0, "Z": 0, "PDT": -7, "PST": -8, "MDT": -6, "MST": -7, "EDT": -4, "EST": -5]
        let token = text.uppercased()
        if let hours = offsets[token] { return TimeZone(secondsFromGMT: hours * 3600) }
        let numeric = token.replacingOccurrences(of: "UTC", with: "").replacingOccurrences(of: "GMT", with: "")
        guard numeric.range(of: #"^[+-]\d{2}:?\d{2}$"#, options: .regularExpression) != nil else { return nil }
        let digits = numeric.dropFirst().replacingOccurrences(of: ":", with: "")
        guard let hours = Int(digits.prefix(2)), let minutes = Int(digits.suffix(2)),
              hours <= 14, minutes < 60, hours < 14 || minutes == 0 else { return nil }
        return TimeZone(secondsFromGMT: (numeric.hasPrefix("-") ? -1 : 1) * (hours * 3600 + minutes * 60))
    }
}

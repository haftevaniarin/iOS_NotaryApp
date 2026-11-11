import Foundation

// Date-only Gregorian arithmetic shared by the form and rescission calculator.
// Mirrors src/utils/notary.js; never interpret YYYY-MM-DD as a UTC instant.
nonisolated struct OrderCalendarDay: Equatable, Hashable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    init?(_ value: String) {
        let prefix = String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(10))
        guard prefix.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return nil }
        let parts = prefix.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }
    init?(year: Int, month: Int, day: Int) {
        guard (1...9998).contains(year), (1...12).contains(month), (1...31).contains(day),
              let date = Self.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)),
              Self.calendar.component(.year, from: date) == year,
              Self.calendar.component(.month, from: date) == month,
              Self.calendar.component(.day, from: date) == day else { return nil }
        self.year = year; self.month = month; self.day = day
    }
    init(date: Date, timeZone: TimeZone = .current) {
        let parts = Self.localCalendar(timeZone).dateComponents([.year, .month, .day], from: date)
        year = parts.year!; month = parts.month!; day = parts.day!
    }
    var key: String { String(format: "%04d-%02d-%02d", year, month, day) }
    private var noon: Date { Self.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))! }
    var weekday: Int { Self.calendar.component(.weekday, from: noon) }
    func adding(days: Int) -> Self { Self(date: Self.calendar.date(byAdding: .day, value: days, to: noon)!, timeZone: Self.calendar.timeZone) }
    func date(timeZone: TimeZone = .current) -> Date {
        Self.localCalendar(timeZone).date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }
    func display(timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter(); formatter.calendar = Self.localCalendar(timeZone); formatter.timeZone = timeZone
        formatter.dateStyle = .long; formatter.timeStyle = .none
        return formatter.string(from: date(timeZone: timeZone))
    }
    static func localCalendar(_ timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        return calendar
    }
    private static var calendar: Calendar { localCalendar(TimeZone(secondsFromGMT: 0)!) }
}

nonisolated struct RescissionDeadline: Equatable, Sendable {
    struct SkippedDay: Equatable, Sendable {
        let date: OrderCalendarDay
        let reason: String
    }
    let date: OrderCalendarDay
    let skippedDays: [SkippedDay]
}

nonisolated enum RescissionRules {
    // Web getRescissionEstimate / isRescissionEligibleSigning, App.jsx.
    static func applies(to signingType: String) -> Bool { signingType == "Refinance" || signingType == "HELOC" }

    // Web calculateRescissionDeadline / isFederalHoliday, src/utils/notary.js.
    // Observed dates are intentional: a Saturday fixed holiday is observed Friday.
    static func calculate(signingDate: String) -> RescissionDeadline? {
        guard var date = OrderCalendarDay(signingDate) else { return nil }
        var counted = 0, skipped: [RescissionDeadline.SkippedDay] = []
        while counted < 3 {
            date = date.adding(days: 1)
            if date.weekday == 1 { skipped.append(.init(date: date, reason: "Sunday")) }
            else if isFederalHoliday(date) { skipped.append(.init(date: date, reason: "Federal holiday")) }
            else { counted += 1 }
        }
        return RescissionDeadline(date: date, skippedDays: skipped)
    }
    static func isFederalHoliday(_ date: OrderCalendarDay) -> Bool {
        for year in (date.year - 1)...(date.year + 1) where year > 0 && year < 9999 {
            let holidays = [
                observed(year, 1, 1), nthWeekday(year, 1, 2, 3), nthWeekday(year, 2, 2, 3),
                lastMonday(year, 5), observed(year, 6, 19), observed(year, 7, 4),
                nthWeekday(year, 9, 2, 1), nthWeekday(year, 10, 2, 2), observed(year, 11, 11),
                nthWeekday(year, 11, 5, 4), observed(year, 12, 25)
            ]
            if holidays.contains(date) { return true }
        }
        return false
    }
    private static func observed(_ year: Int, _ month: Int, _ day: Int) -> OrderCalendarDay {
        let date = OrderCalendarDay(year: year, month: month, day: day)!
        return date.adding(days: date.weekday == 7 ? -1 : date.weekday == 1 ? 1 : 0)
    }
    private static func nthWeekday(_ year: Int, _ month: Int, _ weekday: Int, _ n: Int) -> OrderCalendarDay {
        let first = OrderCalendarDay(year: year, month: month, day: 1)!
        return first.adding(days: (weekday - first.weekday + 7) % 7 + (n - 1) * 7)
    }
    private static func lastMonday(_ year: Int, _ month: Int) -> OrderCalendarDay {
        let last = OrderCalendarDay(year: year, month: month + 1, day: 1)!.adding(days: -1)
        return last.adding(days: -((last.weekday - 2 + 7) % 7))
    }
}

nonisolated enum OrderRescissionFeedback: Equatable {
    case missingType, missingDate, invalidDate, notApplicable
    case calculated(RescissionDeadline)

    init(signingType: String, signingDate: String) {
        if signingType.isEmpty { self = .missingType }
        else if !RescissionRules.applies(to: signingType) { self = .notApplicable }
        else if signingDate.isEmpty { self = .missingDate }
        else if let deadline = RescissionRules.calculate(signingDate: signingDate) { self = .calculated(deadline) }
        else { self = .invalidDate }
    }
    var value: String {
        switch self {
        case .calculated(let deadline): deadline.date.display()
        case .notApplicable: "Not applicable"
        default: "Not available"
        }
    }
    var message: String {
        switch self {
        case .missingType: "Select a signing type to determine whether rescission applies."
        case .missingDate: "Choose a signing date to calculate the rescission deadline."
        case .invalidDate: "Enter a valid signing date to calculate the rescission deadline."
        case .notApplicable: "Rescission does not apply to this signing type under the app’s rules."
        case .calculated(let deadline): "Based on the signing date, the estimated rescission deadline is \(deadline.date.display()). Confirm with title/escrow."
        }
    }
}

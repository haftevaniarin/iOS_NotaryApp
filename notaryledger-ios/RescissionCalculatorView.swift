import SwiftUI

struct RescissionCalculatorView: View {
    @State private var signingDate = Date()
    @State private var includeSaturday = true

    private var rescissionDate: Date {
        var date = Calendar.current.startOfDay(for: signingDate)
        var countedDays = 0
        while countedDays < 3 {
            date = Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date
            if isBusinessDay(date) {
                countedDays += 1
            }
        }
        return date
    }

    private var disbursementDate: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: rescissionDate) ?? rescissionDate
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NLSpacing.lg) {
                ScreenTitleBlock(
                    title: "Rescission Calculator",
                    subtitle: "Calculate the three-business-day rescission deadline for loan signings."
                )

                NLCard {
                    VStack(alignment: .leading, spacing: NLSpacing.md) {
                        DatePicker("Signing Date", selection: $signingDate, displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .tint(NLColor.navy)

                        Toggle("Count Saturdays as business days", isOn: $includeSaturday)
                            .tint(NLColor.navy)

                        BannerView(
                            kind: .info,
                            message: "Sundays and federal holidays are excluded. Confirm lender-specific holiday handling before relying on a closing package."
                        )
                    }
                }

                NLCard {
                    VStack(alignment: .leading, spacing: NLSpacing.md) {
                        Text("Right to Cancel Expires")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(NLColor.muted)
                        Text(Formatters.displayDate.string(from: rescissionDate))
                            .font(NLFonts.serif(30, weight: .bold))
                            .foregroundColor(NLColor.navy)

                        Divider()

                        DetailRow(label: "Earliest disbursement", value: Formatters.displayDate.string(from: disbursementDate))
                        DetailRow(label: "Signing date", value: Formatters.displayDate.string(from: signingDate))
                    }
                }
            }
            .padding(NLSpacing.lg)
        }
        .background(ParchmentBackground())
    }

    private func isBusinessDay(_ date: Date) -> Bool {
        let weekday = Calendar.current.component(.weekday, from: date)
        if weekday == 1 { return false }
        if weekday == 7 && !includeSaturday { return false }
        return !Self.fixedFederalHolidayMonthDays.contains(monthDay(for: date))
    }

    private func monthDay(for date: Date) -> String {
        let comps = Calendar.current.dateComponents([.month, .day], from: date)
        return "\(comps.month ?? 0)-\(comps.day ?? 0)"
    }

    private static let fixedFederalHolidayMonthDays = [
        "1-1",
        "6-19",
        "7-4",
        "11-11",
        "12-25"
    ]
}

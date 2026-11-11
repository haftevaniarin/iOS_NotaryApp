import SwiftUI

struct RescissionCalculatorView: View {
    @State private var signingDate = Date()
    private var estimate: RescissionDeadline? {
        RescissionRules.calculate(signingDate: OrderCalendarDay(date: signingDate).key)
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
                        NLDateField(title: "Signing Date", selection: $signingDate)
                            .datePickerStyle(.compact).tint(NLColor.navy)
                        BannerView(kind: .info, message: "Saturdays count as business days. Sundays and observed federal holidays are excluded, using the same calendar as the web app.")
                    }
                }
                if let estimate {
                    NLCard {
                        VStack(alignment: .leading, spacing: NLSpacing.md) {
                            Text("Right to Cancel Expires").font(NLTypography.label).foregroundStyle(NLColor.muted)
                            Text(estimate.date.display()).font(NLTypography.sectionTitle).foregroundStyle(NLColor.navy)
                            Divider()
                            DetailRow(label: "Earliest disbursement", value: estimate.date.adding(days: 1).display())
                            DetailRow(label: "Signing date", value: OrderCalendarDay(date: signingDate).display())
                            ForEach(estimate.skippedDays, id: \.date) { skipped in
                                DetailRow(label: skipped.reason, value: skipped.date.display())
                            }
                        }
                    }
                }
                Text("This estimate assumes signing and delivery of the required rescission notice and disclosures occur on the same date. Confirm timing with title/escrow.")
                    .font(NLTypography.caption).foregroundStyle(NLColor.muted)
            }.nlScreenPadding()
        }.background(ParchmentBackground())
    }
}

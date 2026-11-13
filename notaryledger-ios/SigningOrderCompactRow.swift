import SwiftUI

struct SigningOrderCompactRow: View {
    let order: SigningOrder

    var body: some View {
        HStack(alignment: .top, spacing: NLSpacing.md) {
            VStack(alignment: .leading, spacing: NLSpacing.xs) {
                Text(order.customerName)
                    .font(NLTypography.bodyStrong)
                    .foregroundColor(NLColor.ink)
                    .lineLimit(1)
                Text(order.signerName)
                    .font(NLTypography.caption)
                    .foregroundColor(NLColor.muted)
                Text([order.displayDate, order.time].compactMap { $0 }.joined(separator: " at "))
                    .font(NLTypography.caption)
                    .foregroundColor(NLColor.muted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: NLSpacing.xs) {
                Text(order.fee.currencyString)
                    .font(NLTypography.bodyStrong)
                    .foregroundColor(NLColor.navy)
                StatusBadge(status: order.normalizedStatus)
            }
        }
        .padding(.vertical, 10)
    }
}

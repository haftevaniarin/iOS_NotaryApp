import SwiftUI

struct OrderScheduleFeedbackView: View {
    let model: OrderSchedulingFeedback
    let onViewOrder: (SigningOrder) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let text = model.serverFailure?.message ?? model.refreshError ?? model.conflict?.message {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").accessibilityHidden(true)
                    Text(text).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(model.serverFailure != nil || model.refreshError != nil ? "order-error-schedule" : "order-schedule-warning")
                }.font(NLTypography.caption)
                    .foregroundStyle(model.serverFailure != nil || model.refreshError != nil ? NLColor.danger : NLColor.warning)
                if let order = model.conflictingOrder {
                    Button("View conflicting order") { onViewOrder(order) }
                        .font(NLTypography.bodyStrong).foregroundStyle(NLColor.navy).frame(minHeight: 44)
                        .accessibilityHint("Opens order details while keeping this signing draft.")
                        .accessibilityIdentifier("view-conflicting-order")
                }
                if model.refreshError != nil {
                    Button("Retry schedule check") { Task { try? await model.refresh() } }
                        .font(NLTypography.bodyStrong).frame(minHeight: 44).disabled(model.isRefreshing)
                }
            }
            if model.isRefreshing { ProgressView("Checking schedule…").font(NLTypography.caption).tint(NLColor.navy) }
        }.id("schedule")
    }
}

struct OrderRescissionFeedbackView: View {
    let feedback: OrderRescissionFeedback
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(text: "Estimated rescission date")
            Text(feedback.value).font(NLTypography.bodyStrong).foregroundStyle(NLColor.navy)
                .accessibilityIdentifier("order-rescission-date")
            Label(feedback.message, systemImage: "info.circle")
                .font(NLTypography.caption).foregroundStyle(NLColor.muted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("order-rescission-message")
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .contain)
    }
}

struct ConflictingOrderDetailView: View {
    let order: SigningOrder
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NLSpacing.lg) {
                    ScreenTitleBlock(title: "Order #\(order.id)", subtitle: "Your new signing draft is kept while you review this order.")
                    NLCard {
                        VStack(alignment: .leading, spacing: NLSpacing.md) {
                            DetailRow(label: "Signer", value: order.signerName)
                            DetailRow(label: "Company", value: order.customerName)
                            if let start = OrderScheduleRules.timestamp(for: order) {
                                DetailRow(label: "Appointment", value: start.formatted(date: .long, time: .shortened))
                                DetailRow(label: "Time zone", value: TimeZone.current.identifier)
                            }
                            DetailRow(label: "Status", value: order.normalizedStatus.rawValue)
                            DetailRow(label: "Invoice number", value: order.invoiceNumber)
                        }
                    }
                }.nlScreenPadding()
            }.background(ParchmentBackground())
                .navigationTitle("Conflicting Order").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.frame(minHeight: 44) } }
        }
    }
}

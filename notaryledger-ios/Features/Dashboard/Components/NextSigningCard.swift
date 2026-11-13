import SwiftUI

struct NextSigningCard: View {
    let signing: Signing?
    let onNavigate: (Signing) -> Void
    let onOpen: (Signing) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var detail: String {
        guard let signing else { return "" }
        let distance = signing.distanceMiles.map { $0.formatted(.number.precision(.fractionLength(0...1))) + " mi" }
        return [signing.address.isEmpty ? "Address not available" : signing.address, distance, signing.fee.formatted(.currency(code: signing.currencyCode))]
            .compactMap { $0 }.joined(separator: " · ")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("NEXT SIGNING · TODAY").font(DashboardTheme.body(11, weight: .semibold)).tracking(1.1).foregroundStyle(Color.brass)
            if let signing {
                VStack(alignment: .leading, spacing: 6) {
                    Text(signing.startsAt, format: .dateTime.hour().minute())
                        .font(DashboardTheme.heading(40, medium: true)).foregroundStyle(Color.parchment)
                    Text("\(signing.signerName) · \(signing.loanType)")
                        .font(DashboardTheme.body(16, weight: .medium)).foregroundStyle(Color.parchment)
                    Text(detail).font(DashboardTheme.body(14)).foregroundStyle(Color.onInkMuted)
                }.fixedSize(horizontal: false, vertical: true).accessibilityElement(children: .combine)
                ViewThatFits(in: .horizontal) {
                    if !dynamicTypeSize.isAccessibilitySize { HStack(spacing: 10) { navigate(signing); open(signing) } }
                    VStack(spacing: 10) { navigate(signing); open(signing) }
                }.padding(.top, 4)
            } else {
                Text("No signings today").font(DashboardTheme.heading(26)).foregroundStyle(Color.parchment)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.ink, in: RoundedRectangle(cornerRadius: DashboardTheme.nextSigningRadius))
    }
    private func navigate(_ signing: Signing) -> some View {
        Button { onNavigate(signing) } label: {
            HStack(spacing: 8) { Image(systemName: "location").accessibilityHidden(true); Text("Navigate") }
        }
            .buttonStyle(DashboardButtonStyle()).disabled(signing.address.isEmpty)
            .accessibilityHint(signing.address.isEmpty ? "No address is available for this signing." : "Opens driving directions in Apple Maps.")
            .accessibilityIdentifier("dashboard-navigate")
    }
    private func open(_ signing: Signing) -> some View {
        Button { onOpen(signing) } label: {
            HStack(spacing: 8) { Image(systemName: "doc.text").accessibilityHidden(true); Text("Open file") }
        }
            .buttonStyle(DashboardButtonStyle(primary: false)).accessibilityIdentifier("dashboard-open-file")
    }
}

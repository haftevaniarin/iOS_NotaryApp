import SwiftUI

struct UpcomingList: View {
    let signings: [Signing]
    let onSelect: (Signing) -> Void
    let onSeeAll: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Coming up").font(DashboardTheme.heading()).foregroundStyle(Color.ink).accessibilityAddTraits(.isHeader)
                Spacer()
                Button("See all", action: onSeeAll).font(DashboardTheme.body(13, weight: .semibold)).foregroundStyle(Color.brassText)
                    .frame(minWidth: 44, minHeight: 44).accessibilityIdentifier("dashboard-see-all")
            }
            DashboardCard {
                VStack(spacing: 0) {
                    if signings.isEmpty {
                        Text("Your next appointments will appear here.").font(DashboardTheme.body(14)).foregroundStyle(Color.muted)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                    }
                    ForEach(signings) { signing in
                        Button { onSelect(signing) } label: { UpcomingRow(signing: signing) }.buttonStyle(.plain)
                        if signing.id != signings.last?.id { Rectangle().fill(Color.divider).frame(height: 1).padding(.horizontal, 16).accessibilityHidden(true) }
                    }
                }
            }
        }
    }
}

private struct UpcomingRow: View {
    let signing: Signing
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption) private var dateWidth: CGFloat = 44
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(spacing: 2) {
                Text(signing.startsAt, format: .dateTime.weekday(.abbreviated))
                    .textCase(.uppercase).font(DashboardTheme.body(11, weight: .semibold)).foregroundStyle(Color.brassText)
                Text(signing.startsAt, format: .dateTime.day()).font(DashboardTheme.heading(22)).foregroundStyle(Color.ink)
            }.frame(width: dateWidth).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(signing.signerName).font(DashboardTheme.body(15, weight: .semibold)).foregroundStyle(Color.ink)
                Text(signing.loanType).font(DashboardTheme.body(13)).foregroundStyle(Color.muted)
                if dynamicTypeSize.isAccessibilitySize { time }
            }.frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            if !dynamicTypeSize.isAccessibilitySize { time }
        }.padding(16).frame(minHeight: 76)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(signing.signerName), \(signing.loanType), \(signing.startsAt.formatted(date: .complete, time: .shortened))")
    }
    private var time: some View { Text(signing.startsAt, format: .dateTime.hour().minute()).font(DashboardTheme.body(13, weight: .medium)).foregroundStyle(Color.ink) }
}

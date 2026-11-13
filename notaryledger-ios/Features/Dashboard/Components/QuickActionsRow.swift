import SwiftUI

struct QuickActionsRow: View {
    let onSelect: (DashboardRoute) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let actions: [DashboardRoute] = [.signing, .expense, .mileage]
    var body: some View {
        ViewThatFits(in: .horizontal) {
            if !dynamicTypeSize.isAccessibilitySize {
                HStack(spacing: 10) { ForEach(actions) { action in actionButton(action) } }
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(actions) { action in actionButton(action) }
            }
        }
    }
    private func actionButton(_ action: DashboardRoute) -> some View {
        Button { onSelect(action) } label: {
            DashboardCard {
                VStack(spacing: 8) {
                    Image(systemName: action.systemImage).font(.system(size: 20)).foregroundStyle(Color.brassText).accessibilityHidden(true)
                    Text(label(action)).font(DashboardTheme.body(12, weight: .semibold)).foregroundStyle(Color.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }.padding(.horizontal, 4).padding(.vertical, 12).frame(maxWidth: .infinity, minHeight: 72)
            }
        }.buttonStyle(.plain).accessibilityLabel(label(action)).accessibilityIdentifier("dashboard-action-\(action.id)")
    }
    private func label(_ route: DashboardRoute) -> String { route == .signing ? "Signing" : route == .expense ? "Expense" : route.title }
}

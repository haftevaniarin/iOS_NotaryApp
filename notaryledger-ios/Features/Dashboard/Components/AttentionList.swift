import SwiftUI

struct AttentionList: View {
    let items: [AttentionItem]
    let onSelect: (DashboardRoute) -> Void
    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Needs attention").font(DashboardTheme.heading()).foregroundStyle(Color.ink).accessibilityAddTraits(.isHeader)
                ForEach(items) { item in
                    Button { onSelect(item.route) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.systemImage).font(.system(size: 17)).foregroundStyle(Color.brassText)
                                .frame(width: 36, height: 36).background(Color.brassTint, in: RoundedRectangle(cornerRadius: 10)).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title).font(DashboardTheme.body(15, weight: .semibold)).foregroundStyle(Color.ink)
                                Text(item.subtitle).font(DashboardTheme.body(13)).foregroundStyle(Color.muted)
                            }.frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.muted).accessibilityHidden(true)
                        }.padding(.vertical, 10).frame(minHeight: 64)
                    }.buttonStyle(.plain).accessibilityElement(children: .ignore).accessibilityLabel("\(item.title). \(item.subtitle)")
                }
            }
        }
    }
}

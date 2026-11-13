import SwiftUI

enum Theme {
    static let inkNavy = Color(hex: 0x1B2A41)
    static let navyRaised = Color(hex: 0x26385A)
    static let navyBorder = Color(hex: 0x3A4D70)
    static let parchment = Color(hex: 0xF5EFE0)
    static let parchmentCard = Color(hex: 0xFBF7EC)
    static let parchmentLine = Color(hex: 0xD6C9A8)
    static let parchmentTrack = Color(hex: 0xE4DAC3)
    static let brass = Color(hex: 0xD9B877)
    static let brassDeep = Color(hex: 0x8A6A2B)
    static let brassText = Color(hex: 0x6B5220)
    static let mutedOnNavy = Color(hex: 0xD8D2C2)
    static let noticeFill = Color(hex: 0xF0E6D4)
    static let noticeBorder = Color(hex: 0xD9C7A3)
    static let mutedText = Color(hex: 0x4A4A48)
    static let activeGreenFill = Color(hex: 0xE3EBDD)
    static let activeGreenText = Color(hex: 0x3F5B3A)
    static let disabledButton = Color(hex: 0x4F5B73)
}

private extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1)
    }
}

struct BillingActionStyle: ButtonStyle {
    var fill = Theme.inkNavy
    var text = Theme.parchment
    var height: CGFloat = 52
    var radius: CGFloat = 14
    var disabledFill: Color?
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(NLTypography.bodyStrong)
            .foregroundStyle(text).frame(maxWidth: .infinity, minHeight: height)
            .padding(.horizontal, 12)
            .background(enabled ? fill : disabledFill ?? fill, in: RoundedRectangle(cornerRadius: radius))
            .opacity(enabled ? configuration.isPressed ? 0.8 : 1 : disabledFill != nil ? 1 : 0.5)
    }
}

struct BillingPanel<Content: View>: View {
    var border: Color
    var borderWidth: CGFloat
    let content: Content
    init(border: Color = Theme.parchmentLine, borderWidth: CGFloat = 1, @ViewBuilder content: () -> Content) {
        self.border = border; self.borderWidth = borderWidth; self.content = content()
    }
    var body: some View {
        content.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.parchmentCard, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(border, lineWidth: borderWidth))
    }
}

struct BillingPill: View {
    let text: String
    let fill: Color
    let textColor: Color
    var body: some View {
        Text(text).font(NLTypography.label).tracking(1.1).foregroundStyle(textColor)
            .padding(.horizontal, 10).padding(.vertical, 6).background(fill, in: Capsule())
    }
}

struct BillingMessage<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    init(text: String) where Content == Text { self.content = Text(text) }
    var body: some View {
        content.font(NLTypography.body).foregroundStyle(Theme.brassText).padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.noticeFill, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.noticeBorder, lineWidth: 1))
    }
}

struct BillingOutlineStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(NLTypography.bodyStrong).foregroundStyle(Theme.inkNavy)
            .frame(maxWidth: .infinity, minHeight: 48).padding(.horizontal, 12)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.inkNavy, lineWidth: 1))
            .opacity(enabled ? configuration.isPressed ? 0.8 : 1 : 0.5)
    }
}

struct BillingIntervalControl: View {
    @Binding var selection: BillingInterval
    var navy = false
    var savings: Int?
    var body: some View {
        HStack(spacing: 0) {
            ForEach(BillingInterval.allCases) { interval in
                Button { selection = interval } label: {
                    Text(interval == .annual && savings != nil ? "Annual · save \(savings!)%" : interval.title)
                        .font(NLTypography.label).lineLimit(1).minimumScaleFactor(0.85)
                        .foregroundStyle(selection == interval ? (navy ? Theme.inkNavy : Theme.parchment) : (navy ? Theme.parchment : Theme.inkNavy))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background {
                            RoundedRectangle(cornerRadius: 9).fill(selection == interval ? (navy ? Theme.brass : Theme.inkNavy) : .clear)
                                .padding(.vertical, 4)
                        }
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel(interval == .annual && savings != nil ? "Annual billing, save \(savings!) percent" : interval.title + " billing")
                    .accessibilityAddTraits(selection == interval ? [.isSelected] : [])
            }
        }.padding(.horizontal, 4).background {
            RoundedRectangle(cornerRadius: 12).fill(navy ? Theme.navyRaised : Theme.parchmentTrack).frame(height: 40)
        }.frame(minHeight: 44)
    }
}

struct BillingNotice: View {
    let text: String
    var navy = false
    var body: some View {
        Label(text, systemImage: "info.circle")
            .font(NLTypography.body).fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(navy ? Theme.parchment : Theme.inkNavy)
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(navy ? Theme.navyRaised : Theme.parchmentCard, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .combine)
    }
}

// Dashboard semantic colors. Keep its palette independent of appearance switching.
extension Color {
    static let ink = Color(hex: 0x1B2A41)
    static let parchment = Color(hex: 0xF5EFE3)
    static let card = Color(hex: 0xFBF8F1)
    static let cardBorder = Color(hex: 0xE2D9C5)
    static let divider = Color(hex: 0xE8E0CE)
    static let brass = Color(hex: 0xD9B567)
    static let brassText = Color(hex: 0x7A5C1F)
    static let brassTint = Color(hex: 0xF1E4C4)
    static let muted = Color(hex: 0x5B6472)
    static let onInkMuted = Color(hex: 0xC9CFDA)
    static let inkOutline = Color(hex: 0x5A6985)
    static let positive = Color(hex: 0x2F6B4F)
}

enum DashboardTheme {
    static let horizontalPadding: CGFloat = 20
    static let sectionGap: CGFloat = 24
    static let cardRadius: CGFloat = 16
    static let nextSigningRadius: CGFloat = 20
    static let buttonRadius: CGFloat = 12
    static func heading(_ size: CGFloat = 20, medium: Bool = false) -> Font {
        .custom(medium ? "NLDisplay-Medium" : "NLDisplay-SemiBold", size: size, relativeTo: size >= 30 ? .largeTitle : .title2)
    }
    static func body(_ size: CGFloat = 14, weight: Font.Weight = .regular) -> Font {
        let name = weight == .semibold ? "NLBody-SemiBold" : weight == .medium ? "NLBody-Medium" : "NLBody-Regular"
        return .custom(name, size: size, relativeTo: size <= 13 ? .caption : .body)
    }
}

struct DashboardCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content.background(Color.card, in: RoundedRectangle(cornerRadius: DashboardTheme.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: DashboardTheme.cardRadius).stroke(Color.cardBorder, lineWidth: 1))
    }
}

struct DashboardButtonStyle: ButtonStyle {
    var primary = true
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(DashboardTheme.body(14, weight: .semibold))
            .foregroundStyle(primary ? Color.ink : Color.parchment)
            .padding(.horizontal, 10).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(primary ? Color.brass : .clear, in: RoundedRectangle(cornerRadius: DashboardTheme.buttonRadius))
            .overlay(RoundedRectangle(cornerRadius: DashboardTheme.buttonRadius).stroke(primary ? .clear : Color.inkOutline, lineWidth: 1))
            .opacity(!enabled ? 0.5 : configuration.isPressed ? 0.8 : 1)
    }
}

import SwiftUI

enum NLColor {
    static let parchment = Color(red: 0.97, green: 0.94, blue: 0.86)
    static let parchmentDeep = Color(red: 0.91, green: 0.86, blue: 0.74)
    static let navy = Color(red: 0.07, green: 0.15, blue: 0.28)
    static let navySoft = Color(red: 0.13, green: 0.24, blue: 0.39)
    static let brass = Color(red: 0.72, green: 0.54, blue: 0.25)
    static let ink = Color(red: 0.10, green: 0.10, blue: 0.11)
    static let muted = Color(red: 0.40, green: 0.38, blue: 0.34)
    static let panel = Color.white.opacity(0.82)
    static let line = Color.black.opacity(0.10)
}

enum NLSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
}

struct ParchmentBackground: View {
    var body: some View {
        LinearGradient(
            colors: [NLColor.parchment, Color(red: 0.99, green: 0.97, blue: 0.91)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .padding(.horizontal, 14)
            .background(configuration.isPressed ? NLColor.navySoft : NLColor.navy)
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(configuration.isPressed ? NLColor.parchmentDeep : Color.white.opacity(0.75))
            .foregroundColor(NLColor.navy)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(NLColor.brass.opacity(0.5), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct PanelModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(NLSpacing.lg)
            .background(NLColor.panel)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(NLColor.line, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

extension View {
    func nlPanel() -> some View {
        modifier(PanelModifier())
    }
}

struct StatusBadge: View {
    let status: SigningStatus

    private var colors: (foreground: Color, background: Color) {
        switch status {
        case .scheduled:
            return (NLColor.navy, Color.blue.opacity(0.12))
        case .pending:
            return (Color.orange.opacity(0.9), Color.orange.opacity(0.15))
        case .overdue:
            return (Color.red.opacity(0.85), Color.red.opacity(0.12))
        case .paid:
            return (Color.green.opacity(0.8), Color.green.opacity(0.14))
        case .cancelled:
            return (NLColor.muted, Color.gray.opacity(0.18))
        }
    }

    var body: some View {
        Text(status.rawValue)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .foregroundColor(colors.foreground)
            .background(colors.background)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

struct ErrorBanner: View {
    let message: String

    var body: some View {
        if !message.isEmpty {
            Text(message)
                .font(.footnote)
                .foregroundColor(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.red.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

struct EmptyStateView: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        VStack(spacing: NLSpacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 36))
                .foregroundColor(NLColor.brass)
            Text(title)
                .font(.headline)
                .foregroundColor(NLColor.ink)
            Text(message)
                .font(.subheadline)
                .foregroundColor(NLColor.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

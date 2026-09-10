import SwiftUI
import UIKit

enum NLColor {
    static let parchment = Color(red: 0.980, green: 0.965, blue: 0.925) // #FAF6EC
    static let parchmentDeep = Color(red: 0.941, green: 0.910, blue: 0.843)
    static let navy = Color(red: 0.106, green: 0.165, blue: 0.290) // #1B2A4A
    static let navySoft = Color(red: 0.180, green: 0.251, blue: 0.400) // #2E4066
    static let brass = Color(red: 0.722, green: 0.537, blue: 0.357) // #B8895B
    static let ink = navy
    static let muted = Color(red: 0.357, green: 0.392, blue: 0.447) // #5B6472
    static let panel = Color.white
    static let line = Color(red: 0.894, green: 0.867, blue: 0.796) // #E4DDCB
    static let warning = Color(red: 0.549, green: 0.318, blue: 0.078)
    static let success = Color(red: 0.102, green: 0.408, blue: 0.267)
    static let danger = Color(red: 0.690, green: 0.157, blue: 0.145)
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
        NLColor.parchment
        .ignoresSafeArea()
    }
}

struct NLFonts {
    static func serif(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}

struct NLSeal: View {
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            Circle()
                .stroke(style: StrokeStyle(lineWidth: max(1.2, size * 0.035), dash: [3, 3]))
                .foregroundColor(NLColor.brass)
            Circle()
                .fill(NLColor.navy)
                .padding(size * 0.13)
            Text("NL")
                .font(.system(size: size * 0.28, weight: .bold, design: .serif))
                .foregroundColor(NLColor.parchment)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Notary Ledger")
    }
}

struct BrandLockup: View {
    var compact = false

    var body: some View {
        HStack(spacing: NLSpacing.sm) {
            NLSeal(size: compact ? 34 : 40)
            VStack(alignment: .leading, spacing: 0) {
                Text("Notary Ledger")
                    .font(NLFonts.serif(compact ? 17 : 19, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text("SIGNING AGENT DESK")
                    .font(.system(size: compact ? 8 : 9, weight: .semibold))
                    .tracking(1.1)
                    .foregroundColor(NLColor.brass)
                    .lineLimit(1)
            }
        }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
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
                    .stroke(NLColor.line, lineWidth: 1)
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
            BannerView(kind: .error, message: message)
        }
    }
}

enum BannerKind {
    case warning
    case error
    case success
    case info

    var icon: String {
        switch self {
        case .warning: "exclamationmark.triangle"
        case .error: "xmark.octagon"
        case .success: "checkmark.seal"
        case .info: "info.circle"
        }
    }

    var foreground: Color {
        switch self {
        case .warning: NLColor.warning
        case .error: NLColor.danger
        case .success: NLColor.success
        case .info: NLColor.navy
        }
    }

    var background: Color {
        foreground.opacity(0.10)
    }
}

struct BannerView: View {
    let kind: BannerKind
    let message: String

    var body: some View {
        if !message.isEmpty {
            HStack(alignment: .top, spacing: NLSpacing.sm) {
                Image(systemName: kind.icon)
                    .font(.subheadline.weight(.semibold))
                    .padding(.top, 1)
                Text(message)
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .foregroundColor(kind.foreground)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(kind.background)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(kind.foreground.opacity(0.18), lineWidth: 1)
            )
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
                .font(NLFonts.serif(19, weight: .semibold))
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

struct NLCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
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

struct ScreenTitleBlock: View {
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(NLFonts.serif(28, weight: .bold))
                .foregroundColor(NLColor.navy)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(NLColor.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FieldLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundColor(NLColor.navySoft)
    }
}

struct NLTextField: View {
    let title: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel(text: title)
            TextField(title, text: $text)
                .keyboardType(keyboardType)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(NLColor.panel)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(NLColor.line, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

struct NLSecureField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel(text: title)
            SecureField(title, text: $text)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(NLColor.panel)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(NLColor.line, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

struct ActionPill: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundColor(NLColor.navy)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(NLColor.panel)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(NLColor.line, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

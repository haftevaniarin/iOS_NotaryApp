import SwiftUI
import UIKit
import CoreText

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

// App.jsx mobile rules: <=640px, <=980px, and the wide layout.
enum NLLayout {
    static func horizontalInset(for width: CGFloat) -> CGFloat { width <= 640 ? 14 : width <= 980 ? 18 : 32 }
    static func verticalInset(for width: CGFloat) -> CGFloat { width <= 640 ? 16 : width <= 980 ? 22 : 26 }
    static func metricColumns(for width: CGFloat) -> Int { width <= 640 ? 1 : width <= 980 ? 2 : 5 }
}

private struct NLViewportWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = 390
}

private struct NLBusinessCardFieldsKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var nlBusinessCardFields: Bool {
        get { self[NLBusinessCardFieldsKey.self] }
        set { self[NLBusinessCardFieldsKey.self] = newValue }
    }
    var nlViewportWidth: CGFloat {
        get { self[NLViewportWidthKey.self] }
        set { self[NLViewportWidthKey.self] = newValue }
    }
}

struct NLScreenPadding: ViewModifier {
    @Environment(\.nlViewportWidth) private var width

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, NLLayout.horizontalInset(for: width))
            .padding(.vertical, NLLayout.verticalInset(for: width))
            .frame(maxWidth: 1280)
            .frame(maxWidth: .infinity)
    }
}

enum NLTypography {
    static let body = NLFonts.sans(13.5)
    static let bodyStrong = NLFonts.sans(13.5, weight: .semibold)
    static let input = NLFonts.sans(14)
    static let label = NLFonts.sans(12, weight: .semibold)
    static let caption = NLFonts.sans(12)
    static let small = NLFonts.sans(11.5)
    static let cardTitle = NLFonts.serif(15)
    static let sectionTitle = NLFonts.serif(19)
    static let metric = NLFonts.mono(20, weight: .semibold)
}

struct ParchmentBackground: View {
    var body: some View {
        NLColor.parchment
        .ignoresSafeArea()
    }
}

struct NLFonts {
    static func registerBundledFonts() {
        for url in Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [] {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        let navigation = UINavigationBarAppearance()
        navigation.configureWithOpaqueBackground()
        navigation.backgroundColor = UIColor(NLColor.parchment)
        navigation.titleTextAttributes = [.font: UIFont(name: "NLDisplay-SemiBold", size: 19) ?? UIFont.systemFont(ofSize: 19)]
        navigation.largeTitleTextAttributes = [.font: UIFont(name: "NLDisplay-SemiBold", size: 23) ?? UIFont.systemFont(ofSize: 23)]
        UINavigationBar.appearance().standardAppearance = navigation
        UINavigationBar.appearance().scrollEdgeAppearance = navigation
        UIBarButtonItem.appearance().setTitleTextAttributes([.font: UIFont(name: "NLBody-Regular", size: 13.5) ?? UIFont.systemFont(ofSize: 13.5)], for: .normal)
    }

    static func serif(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .custom("NLDisplay-\(face(for: weight))", size: size, relativeTo: .body)
    }

    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("NLBody-\(face(for: weight))", size: size, relativeTo: .body)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(weight == .regular ? "IBMPlexMono-Regular" : "IBMPlexMono-Medium", size: size, relativeTo: .body)
    }

    private static func face(for weight: Font.Weight) -> String {
        switch weight {
        case .bold, .heavy, .black: "Bold"
        case .semibold: "SemiBold"
        case .medium: "Medium"
        default: "Regular"
        }
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
                .font(NLFonts.serif(size * 0.3125))
                .foregroundColor(NLColor.parchment)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Notary Ledger")
    }
}

struct PlanBadge: View {
    let billing: BillingStatusPayload?
    var unavailable = false

    private var foreground: Color {
        guard let billing else { return NLColor.muted }
        return billing.hasProAccess ? Color(red: 63/255, green: 107/255, blue: 75/255) : Color(red: 138/255, green: 106/255, blue: 60/255)
    }
    private var background: Color {
        guard let billing else { return NLColor.parchment }
        return billing.hasProAccess ? Color(red: 228/255, green: 239/255, blue: 231/255) : Color(red: 244/255, green: 235/255, blue: 219/255)
    }
    var body: some View {
        Text(billing?.planLabel ?? (unavailable ? "Plan unavailable" : "Loading plan..."))
            .font(NLFonts.sans(10.5, weight: .bold)).tracking(0.42)
            .foregroundColor(foreground)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(background, in: Capsule())
            .overlay(Capsule().stroke(foreground.opacity(0.2), lineWidth: 1))
            .fixedSize()
            .accessibilityLabel(billing.map { "Current plan: \($0.hasProAccess ? "Pro" : "Free")" } ?? (unavailable ? "Plan unavailable" : "Loading plan"))
    }
}

struct BrandLockup: View {
    var compact = false

    var body: some View {
        HStack(spacing: NLSpacing.sm) {
            NLSeal(size: compact ? 30 : 34)
            VStack(alignment: .leading, spacing: 0) {
                Text("Notary Ledger")
                    .font(NLFonts.serif(compact ? 16 : 16.5))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text("SIGNING AGENT DESK")
                    .font(NLFonts.sans(compact ? 10 : 10.5))
                    .tracking(0.4)
                    .foregroundColor(Color(red: 0.604, green: 0.651, blue: 0.761))
                    .lineLimit(1)
            }
        }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(NLTypography.bodyStrong)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .background(configuration.isPressed ? NLColor.navySoft : NLColor.navy)
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(NLTypography.bodyStrong)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
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
            .padding(20)
            .background(NLColor.panel)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(NLColor.line, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

extension View {
    func nlScreenPadding() -> some View { modifier(NLScreenPadding()) }

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
            .font(NLFonts.sans(11.5, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .foregroundColor(colors.foreground)
            .background(colors.background)
            .clipShape(Capsule())
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
                    .font(NLTypography.bodyStrong)
                    .padding(.top, 1)
                Text(message)
                    .font(NLTypography.body)
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
                .font(NLFonts.serif(18))
                .foregroundColor(NLColor.ink)
            Text(message)
                .font(NLTypography.body)
                .foregroundColor(NLColor.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

struct NLCard<Content: View>: View {
    private let content: Content
    private let inset: CGFloat
    private let radius: CGFloat

    init(inset: CGFloat = 20, radius: CGFloat = 14, @ViewBuilder content: () -> Content) {
        self.inset = inset
        self.radius = radius
        self.content = content()
    }

    var body: some View {
        content
            .padding(inset)
            .background(NLColor.panel)
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(NLColor.line, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

struct NLActionRow<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: NLSpacing.md, content: content)
                .fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: NLSpacing.md, content: content)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct NLForm<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 16, content: content)
                    .nlScreenPadding()
                    .environment(\.nlViewportWidth, geometry.size.width)
            }
        }
        .background(NLColor.parchment)
        .font(NLTypography.input)
        .textFieldStyle(NLFormFieldStyle())
    }
}

struct NLFormSection<Content: View>: View {
    let title: String?
    @ViewBuilder let content: () -> Content

    init(_ title: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        NLCard {
            VStack(alignment: .leading, spacing: 14) {
                if let title { Text(title).font(NLTypography.cardTitle) }
                content()
            }
        }
    }
}

struct NLFormFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(NLTypography.input)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(minHeight: 42)
            .background(Color(red: 0.992, green: 0.988, blue: 0.973))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(NLColor.line, lineWidth: 1))
    }
}

struct ScreenTitleBlock: View {
    @Environment(\.nlViewportWidth) private var width
    let title: String
    let subtitle: String?
    var titleSize: CGFloat? = nil
    var titleWeight: Font.Weight = .semibold
    var subtitleSize: CGFloat = 13.5

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(NLFonts.serif(titleSize ?? (width <= 640 ? 23 : 28), weight: titleWeight))
                .tracking(-0.46)
                .foregroundColor(NLColor.navy)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(NLFonts.sans(subtitleSize))
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundColor(NLColor.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FieldLabel: View {
    @Environment(\.nlBusinessCardFields) private var businessCard
    let text: String

    var body: some View {
        Text(text)
            .font(businessCard ? NLFonts.sans(14, weight: .semibold) : NLTypography.label)
            .tracking(0.24)
            .foregroundColor(NLColor.muted)
    }
}

struct NLTextField: View {
    @Environment(\.nlBusinessCardFields) private var businessCard
    let title: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var showsLabel = true
    var accessibilityName: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if showsLabel { FieldLabel(text: title) }
            TextField(title, text: $text)
                .accessibilityLabel(accessibilityName ?? title)
                .accessibilityIdentifier(accessibilityName ?? title)
                .font(businessCard ? NLFonts.sans(15) : NLTypography.input)
                .keyboardType(keyboardType)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .frame(minHeight: businessCard ? 46 : 42)
                .background(Color(red: 0.992, green: 0.988, blue: 0.973))
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
                .font(NLTypography.input)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .frame(minHeight: 42)
                .background(Color(red: 0.992, green: 0.988, blue: 0.973))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(NLColor.line, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

struct NLSelectField<Selection: Hashable, Content: View>: View {
    let title: String
    @Binding var selection: Selection
    let value: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel(text: title)
            Menu {
                Picker(title, selection: $selection, content: content)
            } label: {
                HStack(spacing: 8) {
                    Text(value).multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down").font(NLFonts.sans(11))
                }
                .font(NLTypography.input)
                .foregroundStyle(NLColor.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .frame(minHeight: 42)
                .background(Color(red: 0.992, green: 0.988, blue: 0.973))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(NLColor.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(value)
        }
    }
}

struct NLTextArea: View {
    @Environment(\.nlBusinessCardFields) private var businessCard
    let title: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel(text: title)
            TextEditor(text: $text)
                .font(businessCard ? NLFonts.sans(15) : NLTypography.input)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 84)
                .background(Color(red: 0.992, green: 0.988, blue: 0.973))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(NLColor.line, lineWidth: 1))
                .accessibilityLabel(title)
        }
    }
}

struct NLTimeField: View {
    let title: String
    @Binding var time: String
    @State private var draftTime = Date()
    @State private var isChoosingTime = false

    private var displayValue: String {
        guard let date = TimeParser.date(from: time) else { return time.isEmpty ? "Select time" : time }
        return date.formatted(date: .omitted, time: .shortened)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel(text: title)
            Button {
                draftTime = TimeParser.date(from: time) ?? Date()
                isChoosingTime = true
            } label: {
                HStack {
                    Text(displayValue)
                    Spacer()
                    Image(systemName: "clock")
                }
                .font(NLTypography.input)
                .foregroundStyle(time.isEmpty ? NLColor.muted : NLColor.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .frame(minHeight: 42)
                .background(Color(red: 0.992, green: 0.988, blue: 0.973))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(NLColor.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(time.isEmpty ? "Not set" : displayValue)
        }
        .sheet(isPresented: $isChoosingTime) {
            NavigationStack {
                VStack(spacing: 16) {
                    DatePicker(title, selection: $draftTime, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .accessibilityLabel(title)
                    if !time.isEmpty {
                        Button("Clear Time", role: .destructive) {
                            time = ""
                            isChoosingTime = false
                        }
                    }
                }
                .padding(14)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { isChoosingTime = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            time = TimeParser.apiTimeString(from: draftTime)
                            isChoosingTime = false
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }
}

struct NLDateField: View {
    let title: String
    @Binding var selection: Date
    @State private var isChoosingDate = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel(text: title)
            Button { isChoosingDate = true } label: {
                HStack {
                    Text(Formatters.displayDate.string(from: selection))
                    Spacer()
                    Image(systemName: "calendar")
                }
                .font(NLTypography.input)
                .foregroundStyle(NLColor.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .frame(minHeight: 42)
                .background(Color(red: 0.992, green: 0.988, blue: 0.973))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(NLColor.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(Formatters.displayDate.string(from: selection))
        }
        .sheet(isPresented: $isChoosingDate) {
            NavigationStack {
                DatePicker(title, selection: $selection, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(NLColor.navy)
                    .padding(14)
                    .navigationTitle(title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { isChoosingDate = false } } }
            }
            .presentationDetents([.medium, .large])
        }
    }
}

struct ActionPill: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(NLTypography.bodyStrong)
            .foregroundColor(NLColor.navy)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(NLColor.panel)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(NLColor.line, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

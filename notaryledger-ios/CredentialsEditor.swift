import SwiftUI

struct CredentialsEditor: View {
    @State private var credentials = Credentials()
    @State private var loaded = false
    @State private var busy = false
    @State private var error = ""
    @State private var success = ""
    private let sections: [(String, [(String, WritableKeyPath<Credentials, String?>)])] = [
        ("Commission", [("Commission number", \.commissionNumber), ("Issuing state", \.commissionState), ("Start date", \.commissionStartDate), ("Expiration date", \.commissionExpirationDate)]),
        ("E&O Insurance", [("Provider", \.eoProvider), ("Policy number", \.eoPolicyNumber), ("Coverage amount", \.eoCoverageAmount), ("Start date", \.eoStartDate), ("Expiration date", \.eoExpirationDate)]),
        ("Background Check", [("Provider", \.backgroundCheckProvider), ("Completed date", \.backgroundCheckCompletedDate), ("Expiration date", \.backgroundCheckExpirationDate)]),
        ("Certification", [("Certification name", \.certificationName), ("Expiration date", \.certificationExpirationDate)])
    ]
    var body: some View {
        NLCard {
            VStack(alignment: .leading, spacing: NLSpacing.md) {
                Text("Credentials").font(NLTypography.cardTitle).foregroundColor(NLColor.navy)
                Text("Dates use YYYY-MM-DD. Clear all fields in a credential to remove it.").font(NLTypography.caption).foregroundColor(NLColor.muted)
                ErrorBanner(message: error)
                BannerView(kind: .success, message: success)
                ForEach(sections.indices, id: \.self) { index in
                    let section = sections[index]
                    Text(section.0).font(NLFonts.serif(15)).foregroundColor(NLColor.navy)
                    ForEach(section.1.indices, id: \.self) { fieldIndex in
                        let field = section.1[fieldIndex]
                        NLTextField(title: field.0, text: binding(field.1))
                            .disabled(!loaded || busy)
                    }
                    if let value = credentials[keyPath: section.1.last!.1], !value.isEmpty {
                        let status = Self.expirationStatus(value)
                        BannerView(kind: status == "Current" ? .success : .warning, message: status)
                    }
                }
                Button(busy ? "Saving..." : loaded ? "Save Credentials" : "Load Credentials") { Task { if loaded { await save() } else { await load() } } }
                    .buttonStyle(PrimaryButtonStyle()).disabled(busy)
            }
        }.task { await load() }
    }
    private func binding(_ key: WritableKeyPath<Credentials, String?>) -> Binding<String> {
        Binding(get: { credentials[keyPath: key] ?? "" }, set: { credentials[keyPath: key] = $0.nilIfEmpty })
    }
    private func load() async {
        busy = true
        defer { busy = false }
        do { credentials = try await APIService.shared.fetchCredentials(); normalizeDates(); loaded = true; error = "" }
        catch { self.error = error.localizedDescription }
    }
    private func normalizeDates() {
        for (_, fields) in sections {
            for (name, key) in fields where name.lowercased().contains("date") {
                if let value = credentials[keyPath: key], value.contains("T") { credentials[keyPath: key] = String(value.prefix(10)) }
            }
        }
    }
    static func expirationStatus(_ value: String, today: Date = Date()) -> String {
        guard let date = DateParser.date(from: String(value.prefix(10))) else { return "Enter a valid expiration date." }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: today), to: date).day ?? 0
        if days < 0 { return "Expired" }
        if date <= (Calendar.current.date(byAdding: .month, value: 1, to: Calendar.current.startOfDay(for: today)) ?? today) { return "Expires in \(days) days" }
        return "Current"
    }
    private func save() async {
        error = ""; success = ""
        for (_, fields) in sections {
            for (name, key) in fields where name.lowercased().contains("date") {
                if let value = credentials[keyPath: key], !value.isEmpty {
                    let day = String(value.prefix(10))
                    guard let date = DateParser.date(from: day), DateParser.apiDateString(from: date) == day else { error = "Enter a valid \(name.lowercased()) as YYYY-MM-DD."; return }
                    credentials[keyPath: key] = day
                }
            }
        }
        if let completed = credentials.backgroundCheckCompletedDate, let expiration = credentials.backgroundCheckExpirationDate, expiration < completed {
            error = "Background check expiration must be on or after completion."; return
        }
        busy = true
        defer { busy = false }
        do { credentials = try await APIService.shared.updateCredentials(credentials); normalizeDates(); success = "Credentials saved." }
        catch { self.error = error.localizedDescription }
    }
}

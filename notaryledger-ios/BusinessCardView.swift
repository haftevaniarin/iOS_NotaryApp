import SwiftUI

struct BusinessCardView: View {
    @EnvironmentObject private var appState: AppState
    @State private var card = BusinessCard()
    @State private var saved: BusinessCard?
    @State private var loaded = false
    @State private var busy = false
    @State private var error = ""
    @State private var message = ""
    @State private var share: ShareURL?
    private let identity: [(String, WritableKeyPath<BusinessCard, String?>)] = [
        ("Public URL slug", \.slug), ("Display name", \.displayName), ("Professional title", \.professionalTitle), ("Business name", \.businessName), ("Bio", \.bio), ("City", \.city), ("State", \.state)
    ]
    private let contact: [(String, WritableKeyPath<BusinessCard, String?>)] = [
        ("Business phone", \.businessPhone), ("Business email", \.businessEmail), ("Website URL", \.websiteUrl), ("Instagram URL", \.instagramUrl), ("Facebook URL", \.facebookUrl), ("LinkedIn URL", \.linkedinUrl), ("Card photo URL (HTTPS)", \.profilePhotoUrl), ("Logo URL (HTTPS)", \.logoUrl)
    ]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NLSpacing.lg) {
                ScreenTitleBlock(title: "Digital Business Card", subtitle: "Edit your public contact information and control what you share.")
                ErrorBanner(message: error)
                BannerView(kind: .success, message: message)
                NLCard {
                    VStack(alignment: .leading, spacing: NLSpacing.md) {
                        Text(saved?.isPublished == true ? "Published" : "Draft").font(.headline).foregroundColor(NLColor.navy)
                        fields(identity)
                        NLTextField(title: "Service areas (comma separated)", text: listBinding(\.serviceAreas))
                        NLTextField(title: "Languages (comma separated)", text: listBinding(\.languages))
                    }
                }
                NLCard {
                    VStack(alignment: .leading, spacing: NLSpacing.md) {
                        Text("Contact & Privacy").font(.headline).foregroundColor(NLColor.navy)
                        fields(contact)
                        Toggle("Show business phone publicly", isOn: $card.showBusinessPhone)
                        Toggle("Show business email publicly", isOn: $card.showBusinessEmail)
                        Toggle("Use my profile photo publicly", isOn: $card.useProfilePhoto)
                        Text("Publishing makes these details visible to anyone with the link. Hidden phone and email stay private. Your default start address is never included.").font(.caption).foregroundColor(NLColor.muted)
                    }
                }
                Button(loaded ? "Save Card" : "Reload Card") { Task { if loaded { await save() } else { await load() } } }.buttonStyle(PrimaryButtonStyle()).disabled(busy)
                if loaded {
                    Button(saved?.isPublished == true ? "Unpublish" : "Publish") { Task { await publish() } }.buttonStyle(SecondaryButtonStyle()).disabled(busy || saved == nil || saved != card)
                    if saved != card { Text("Save your edits before publishing or sharing.").font(.caption) }
                    if let saved, saved.isPublished, let value = saved.canonicalUrl, let url = URL(string: value), url.scheme == "https" || url.scheme == "http" {
                        Text(value).font(.caption).textSelection(.enabled)
                        ShareLink(item: url) { Label("Share Card", systemImage: "square.and.arrow.up") }.buttonStyle(SecondaryButtonStyle()).disabled(saved != card)
                        Button("Share Contact File") { Task { await shareContact() } }.buttonStyle(SecondaryButtonStyle()).disabled(busy || saved != card)
                    }
                }
                if busy { ProgressView() }
            }.padding(NLSpacing.lg)
        }.background(ParchmentBackground())
            .sheet(item: $share) { ShareSheet(activityItems: [$0.url]) }
            .task { await load() }
    }
    private func fields(_ items: [(String, WritableKeyPath<BusinessCard, String?>)]) -> some View {
        ForEach(items.indices, id: \.self) { i in
            NLTextField(title: items[i].0, text: Binding(get: { card[keyPath: items[i].1] ?? "" }, set: { card[keyPath: items[i].1] = $0.nilIfEmpty }))
                .textInputAutocapitalization(.never).disabled(!loaded || busy)
        }
    }
    private func listBinding(_ key: WritableKeyPath<BusinessCard, [String]>) -> Binding<String> {
        Binding(get: { card[keyPath: key].joined(separator: ", ") }, set: { card[keyPath: key] = $0.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } })
    }
    private func load() async {
        busy = true
        defer { busy = false }
        do { card = try await APIService.shared.fetchBusinessCard(); saved = card; loaded = true; error = "" }
        catch { self.error = error.localizedDescription }
    }
    private func save() async {
        error = ""; message = ""
        if let validation = card.validationMessage() { error = validation; return }
        busy = true
        defer { busy = false }
        do { card = try await APIService.shared.saveBusinessCard(card); saved = card; message = "Card saved." }
        catch { self.error = error.localizedDescription }
    }
    private func publish() async {
        error = ""; message = ""; busy = true
        defer { busy = false }
        do { card = try await APIService.shared.publishBusinessCard(!(saved?.isPublished ?? false)); saved = card; message = card.isPublished ? "Card published." : "Card unpublished." }
        catch { self.error = error.localizedDescription }
    }
    private func shareContact() async {
        guard let saved, saved.isPublished, let slug = saved.slug else { return }
        error = ""; busy = true
        defer { busy = false }
        do { share = ShareURL(url: try await APIService.shared.downloadCardContact(slug: slug)) }
        catch { self.error = error.localizedDescription }
    }

}

import SwiftUI

struct SpreadsheetImportReviewView: View {
    @Environment(\.dismiss) private var dismiss
    let draft: SpreadsheetDraft
    let onImport: (SigningImportResult) -> Void
    @State private var text = ""
    @State private var busy = false
    @State private var error = ""
    var body: some View {
        NavigationStack {
            ZStack {
                ParchmentBackground()
                VStack(alignment: .leading, spacing: NLSpacing.md) {
                    ScreenTitleBlock(title: "Review Spreadsheet", subtitle: draft.filename)
                    Text("Review or edit the spreadsheet text before saving. Keep the header row and separators. Required columns: Customer, Signer, Date, and Fee.").font(.subheadline).foregroundColor(NLColor.muted)
                    ErrorBanner(message: error)
                    TextEditor(text: $text).font(.system(.body, design: .monospaced))
                        .padding(8).background(Color.white).clipShape(RoundedRectangle(cornerRadius: 8)).disabled(busy)
                    Text("Saving imports valid rows together. The server validates rows, skips existing duplicates, and applies your plan limits.").font(.caption).foregroundColor(NLColor.muted)
                }.padding(NLSpacing.lg)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() }.disabled(busy) }
                ToolbarItem(placement: .topBarTrailing) { Button(busy ? "Importing..." : "Save Signings") { Task { await save() } }.disabled(busy || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
        }.onAppear { text = draft.text }.interactiveDismissDisabled(busy)
    }
    private func save() async {
        error = ""; busy = true
        defer { busy = false }
        do {
            let result = try await APIService.shared.importSignings(MultipartFile(fieldName: "file", fileName: draft.filename, mimeType: draft.mimeType, data: Data(text.utf8)))
            onImport(result); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

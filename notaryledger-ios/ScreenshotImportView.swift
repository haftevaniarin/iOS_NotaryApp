import SwiftUI
import PhotosUI
import Vision
import ImageIO
import UniformTypeIdentifiers

struct ScreenshotReviewSource: Identifiable {
    let id = UUID()
    let imageData: Data
    let draft: ScreenshotOrderDraft
}

nonisolated enum ScreenshotTextRecognition {
    static func recognize(_ data: Data) async throws -> ScreenshotOrderDraft {
        // Vision and parsing run away from the UI actor. No image or OCR text leaves the device.
        let worker = Task.detached(priority: .userInitiated) {
            guard data.count <= 10 * 1024 * 1024 else { throw ScreenshotImportError.tooLarge }
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 4096
                  ] as CFDictionary) else { throw ScreenshotImportError.unreadable }
            try Task.checkCancellation()
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.automaticallyDetectsLanguage = true
            do { try VNImageRequestHandler(cgImage: image).perform([request]) }
            catch { throw ScreenshotImportError.recognitionFailed }
            try Task.checkCancellation()
            // Merge observations sharing a baseline, preserving left-to-right label/value columns.
            let observations = (request.results ?? []).sorted { $0.boundingBox.midY > $1.boundingBox.midY }
            var rows: [[VNRecognizedTextObservation]] = []
            for observation in observations {
                if let last = rows.last, let anchor = last.first,
                   abs(anchor.boundingBox.midY - observation.boundingBox.midY) < min(anchor.boundingBox.height, observation.boundingBox.height) * 0.45 {
                    rows[rows.count - 1].append(observation)
                } else { rows.append([observation]) }
            }
            let lines = rows.compactMap { row -> ScreenshotTextLine? in
                let candidates = row.sorted { $0.boundingBox.minX < $1.boundingBox.minX }.compactMap { $0.topCandidates(1).first }
                guard !candidates.isEmpty else { return nil }
                return ScreenshotTextLine(text: candidates.map(\.string).joined(separator: " "), confidence: candidates.map(\.confidence).min() ?? 0)
            }
            return try ScreenshotOrderExtractor.extract(lines)
        }
        return try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    }
}

struct ScreenshotImportView: View {
    var onExtract: ((ScreenshotReviewSource) -> Void)? = nil

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var selection: PhotosPickerItem?
    @State private var source: ScreenshotReviewSource?
    @State private var busy = false
    @State private var error = ""
    @State private var success = false
    @State private var showFileImporter = false
    @State private var pdfDraft: ExtractedSigning?
    @State private var pendingPDF: MultipartFile?
    @State private var showPDFConsent = false

    var body: some View {
        NavigationStack {
            ZStack {
                ParchmentBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: NLSpacing.lg) {
                        ScreenTitleBlock(title: "Extract Order from Screenshot", subtitle: "Extract details for one signing order from a confirmation or assignment. Review and edit before creating the order.")
                        BannerView(kind: .info, message: "Text recognition runs on your device. The screenshot stays on your device. Only the order fields you review and agree to save are sent to your account.")
                        ErrorBanner(message: error)
                        if success { BannerView(kind: .success, message: "Signing order created successfully.") }
                        PhotosPicker(selection: $selection, matching: .images, preferredItemEncoding: .current) {
                            Label("Choose Screenshot", systemImage: "photo")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(busy)
                        .accessibilityHint("Select one screenshot from your photo library for on-device text recognition.")
                        Button(onExtract == nil ? "Choose Image or PDF from Files" : "Choose Image from Files") { showFileImporter = true }
                            .buttonStyle(SecondaryButtonStyle()).disabled(busy)
                        Text(onExtract == nil
                             ? "Images are read on your device. PDFs require your consent to upload for extraction. For multiple orders from a spreadsheet, use Bulk Import Signings."
                             : "Extracted details fill empty fields in your signing form. You’ll return to the form to review and confirm before saving.")
                            .font(NLTypography.caption).foregroundStyle(NLColor.muted)
                        if busy { ProgressView("Extracting order details…").accessibilityIdentifier("screenshot-import-loading") }
                    }.nlScreenPadding()
                }
            }
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() }.disabled(busy) } }
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: onExtract == nil ? [.jpeg, .png, .webP, .pdf] : [.jpeg, .png, .webP]) { result in
                switch result {
                case .success(let url): Task { await readOrderFile(url) }
                case .failure: error = "The file could not be opened. Try again."
                }
            }
            .task(id: selection) {
                guard let selection else { return }
                busy = true; error = ""; success = false
                defer { busy = false }
                do {
                    guard let data = try await selection.loadTransferable(type: Data.self) else { throw ScreenshotImportError.unreadable }
                    let draft = try await ScreenshotTextRecognition.recognize(data)
                    try Task.checkCancellation()
                    review(ScreenshotReviewSource(imageData: data, draft: draft))
                } catch is CancellationError {
                    return
                } catch {
                    self.error = (error as? ScreenshotImportError)?.localizedDescription ?? "The photo could not be read. Try again or choose another screenshot."
                }
                self.selection = nil
            }
            .sheet(item: $source) { source in
                NavigationStack {
                    SigningOrderFormView(order: nil, onSave: { payload in
                        let created = try await APIService.shared.createOrder(payload)
                        appState.upsertOrder(created)
                        success = true
                    }, screenshot: source)
                }
            }
            .sheet(item: $pdfDraft) { draft in
                NavigationStack {
                    SigningOrderFormView(order: nil, onSave: { payload in
                        let created = try await APIService.shared.createOrder(payload)
                        appState.upsertOrder(created)
                        success = true
                    }, extracted: draft)
                }
            }
            .alert("Allow PDF upload?", isPresented: $showPDFConsent) {
                Button("Cancel", role: .cancel) { pendingPDF = nil }
                Button("Upload and Extract") {
                    guard let file = pendingPDF else { return }
                    pendingPDF = nil
                    Task {
                        busy = true
                        defer { busy = false }
                        do { pdfDraft = try await APIService.shared.extractSigning(file) }
                        catch { self.error = "The PDF could not be processed. Try again." }
                    }
                }
            } message: {
                Text("The PDF and its text will be sent to the extraction service. Only continue if you consent to sending its contents.")
            }
        }
    }

    private func review(_ source: ScreenshotReviewSource) {
        if let onExtract {
            onExtract(source)
            dismiss()
        } else {
            self.source = source
        }
    }

    private func readOrderFile(_ url: URL) async {
        error = ""; success = false; busy = true
        defer { busy = false }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 10 * 1024 * 1024 else { throw ScreenshotImportError.tooLarge }
            let type = UTType(filenameExtension: url.pathExtension)
            let data = try Data(contentsOf: url)
            if type?.conforms(to: .image) == true {
                let draft = try await ScreenshotTextRecognition.recognize(data)
                review(ScreenshotReviewSource(imageData: data, draft: draft))
            } else if type?.conforms(to: .pdf) == true && onExtract == nil {
                pendingPDF = MultipartFile(fieldName: "file", fileName: url.lastPathComponent, mimeType: "application/pdf", data: data)
                showPDFConsent = true
            } else {
                error = "Choose an image or PDF for single-order extraction. Use Bulk Import Signings for spreadsheets."
            }
        } catch {
            self.error = (error as? ScreenshotImportError)?.localizedDescription ?? "The file could not be read. Try again or choose another file."
        }
    }
}

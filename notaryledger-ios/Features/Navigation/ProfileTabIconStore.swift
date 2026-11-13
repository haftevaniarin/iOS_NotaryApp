import ImageIO
import Observation
import SwiftUI
import UIKit

struct ProfileTabIdentity: Equatable {
    let userID: String?
    let photoURL: String?
    let initials: String

    init(user: AuthUser?) {
        userID = user?.id
        photoURL = user?.profilePhotoUrl
        let names = [user?.firstName, user?.lastName].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let fullName = user?.fullName.split(whereSeparator: \.isWhitespace).map(String.init) ?? []
        let parts = names.count >= 2 ? names : fullName.isEmpty ? names : fullName
        let first = parts.first?.first.map(String.init) ?? ""
        let last = parts.count > 1 ? parts.last?.first.map(String.init) ?? "" : ""
        let value = (first + last).uppercased()
        initials = value.isEmpty ? user?.email.first.map { String($0).uppercased() } ?? "NL" : value
    }
}

@MainActor @Observable final class ProfileTabIconStore {
    nonisolated deinit {}
    private(set) var identity: ProfileTabIdentity?
    private(set) var isShowingPhoto = false
    private var icon: UIImage?
    private var revision = UUID()
    private let fetch: @MainActor (URL) async throws -> Data

    init(fetch: (@MainActor (URL) async throws -> Data)? = nil) { self.fetch = fetch ?? Self.fetchPhoto }

    func image(for identity: ProfileTabIdentity) -> UIImage {
        if self.identity == identity, let icon { return icon }
        return Self.render(initials: identity.initials)
    }
    func load(_ identity: ProfileTabIdentity) async {
        if self.identity == identity, isShowingPhoto { return }
        let request = UUID(); revision = request
        self.identity = identity; isShowingPhoto = false; icon = Self.render(initials: identity.initials)
        guard let value = identity.photoURL, let url = URL(string: value), url.scheme?.lowercased() == "https", url.host != nil else { return }
        do {
            let data = try await fetch(url)
            try Task.checkCancellation()
            guard revision == request, self.identity == identity, data.count <= 8 * 1024 * 1024,
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 96,
                    kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary) else { return }
            icon = Self.render(initials: identity.initials, photo: UIImage(cgImage: thumbnail))
            isShowingPhoto = true
        } catch {
            // A missing, unreadable, or unavailable photo uses the initials already shown.
            // Never log the photo URL, image bytes, or account details.
        }
    }
    private static func fetchPhoto(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url); request.timeoutInterval = 15
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode) else { throw URLError(.badServerResponse) }
        return data
    }
    private static func render(initials: String, photo: UIImage? = nil) -> UIImage {
        let size = CGSize(width: 28, height: 28)
        let bounds = CGRect(origin: .zero, size: size)
        return UIGraphicsImageRenderer(size: size).image { context in
            context.cgContext.addEllipse(in: bounds); context.cgContext.clip()
            if let photo, photo.size.width > 0, photo.size.height > 0 {
                let scale = max(size.width / photo.size.width, size.height / photo.size.height)
                let scaled = CGSize(width: photo.size.width * scale, height: photo.size.height * scale)
                photo.draw(in: CGRect(x: (size.width - scaled.width) / 2, y: (size.height - scaled.height) / 2, width: scaled.width, height: scaled.height))
            } else {
                UIColor(Color.brassTint).setFill(); context.fill(bounds)
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont(name: "NLBody-SemiBold", size: 11) ?? UIFont.systemFont(ofSize: 11, weight: .semibold),
                    .foregroundColor: UIColor(Color.ink)
                ]
                let text = initials as NSString
                let textSize = text.size(withAttributes: attributes)
                text.draw(at: CGPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2), withAttributes: attributes)
            }
        }.withRenderingMode(.alwaysOriginal)
    }
}

import Foundation
import Testing
import UIKit
@testable import notaryledger_ios

@MainActor struct ProfileTabIconTests {
    private func user(_ id: String, photo: Bool) -> AuthUser {
        var user = AuthUser(id: id, fullName: "Avery Sample Notary", email: "avery@example.test", firstName: "Avery", lastName: "Notary")
        user.profilePhotoUrl = photo ? "https://photos.example.test/\(id).png" : nil
        return user
    }
    private func photo() throws -> Data {
        try #require(UIGraphicsImageRenderer(size: CGSize(width: 40, height: 60)).image { context in
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 40, height: 60))
        }.pngData())
    }
    @Test func existingPhotoBecomesCircularNativeTabImage() async throws {
        let data = try photo()
        let model = ProfileTabIconStore(fetch: { _ in data })
        let identity = ProfileTabIdentity(user: user("first", photo: true))
        await model.load(identity)
        #expect(model.isShowingPhoto)
        #expect(model.image(for: identity).size == CGSize(width: 28, height: 28))
        #expect(model.image(for: identity).renderingMode == .alwaysOriginal)
    }
    @Test func unavailableOrUnreadablePhotoFallsBackToUserInitials() async {
        let identity = ProfileTabIdentity(user: user("first", photo: true))
        #expect(identity.initials == "AN")
        let unavailable = ProfileTabIconStore(fetch: { _ in throw URLError(.notConnectedToInternet) })
        await unavailable.load(identity)
        #expect(!unavailable.isShowingPhoto && unavailable.identity == identity)
        let invalid = ProfileTabIconStore(fetch: { _ in Data("not an image".utf8) })
        await invalid.load(identity)
        #expect(!invalid.isShowingPhoto)
        let noPhoto = ProfileTabIconStore(fetch: { _ in Issue.record("No photo URL must not fetch"); return Data() })
        await noPhoto.load(ProfileTabIdentity(user: user("second", photo: false)))
        #expect(!noPhoto.isShowingPhoto)
    }
    @Test func accountChangeRejectsAnOlderAccountsDelayedPhoto() async throws {
        let data = try photo()
        let signal = AsyncStream<Void>.makeStream()
        var pending: CheckedContinuation<Data, Error>?
        let model = ProfileTabIconStore(fetch: { _ in
            try await withCheckedThrowingContinuation { continuation in pending = continuation; signal.continuation.yield(()) }
        })
        let first = ProfileTabIdentity(user: user("first", photo: true))
        let second = ProfileTabIdentity(user: user("second", photo: false))
        let request = Task { await model.load(first) }
        var iterator = signal.stream.makeAsyncIterator(); await iterator.next()
        await model.load(second)
        pending?.resume(returning: data); await request.value
        #expect(model.identity == second && !model.isShowingPhoto)
    }
}

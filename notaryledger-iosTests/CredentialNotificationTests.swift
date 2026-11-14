import Foundation
import Testing
@testable import notaryledger_ios

@MainActor struct CredentialNotificationTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }

    @Test func includesExpiredTodayAndMonthBoundaryWhileExcludingCurrentMissingAndInvalidDates() throws {
        let today = try #require(CredentialDates.date("2026-01-31", calendar: calendar))
        var credentials = Credentials()
        credentials.commissionExpirationDate = "2026-01-30T00:00:00.000Z"
        credentials.eoExpirationDate = "2026-01-31"
        credentials.backgroundCheckExpirationDate = "2026-02-28"
        credentials.certificationName = "Signing Agent"
        credentials.certificationExpirationDate = "2026-03-01"
        let alerts = CredentialNotification.make(credentials: credentials, today: today, calendar: calendar)
        #expect(alerts.map(\.id) == [.commission, .insurance, .backgroundCheck])
        #expect(alerts[0].status == .expired && alerts[0].message == "Expired on 2026-01-30")
        #expect(alerts[1].message == "Expires today")
        #expect(alerts[2].status == .expiringSoon(days: 28))
        credentials.commissionExpirationDate = nil
        credentials.eoExpirationDate = "invalid"
        credentials.backgroundCheckExpirationDate = "2026-02-29"
        credentials.certificationExpirationDate = "2026-02-01"
        let remaining = CredentialNotification.make(credentials: credentials, today: today, calendar: calendar)
        #expect(remaining.count == 1 && remaining.first?.title == "Signing Agent")
        #expect(CredentialNotification.make(credentials: nil, today: today).isEmpty)
    }

    @Test func savedRenewalsAndRemovalUpdateAlertsWhileUnsavedChangesDoNot() async throws {
        let today = try #require(CredentialDates.date("2026-11-14", calendar: calendar))
        var credentials = Credentials()
        credentials.commissionExpirationDate = "2026-11-01"
        credentials.eoExpirationDate = "2026-11-14"
        let model = CredentialsEditorModel(saved: credentials, persist: { $0 })
        let commission = try #require(CredentialSection.commission.fields.last)
        model.edit(commission, value: "2099-12-31")
        #expect(CredentialNotification.make(credentials: model.saved, today: today).count == 2)
        await model.save()
        #expect(CredentialNotification.make(credentials: model.saved, today: today).map(\.id) == [.insurance])
        for field in CredentialSection.insurance.fields { model.edit(field, value: "") }
        await model.save()
        #expect(CredentialNotification.make(credentials: model.saved, today: today).isEmpty)
    }

    @Test func refreshFailureKeepsSavedAlertsAndRefreshDoesNotOverwriteDrafts() async {
        var credentials = Credentials()
        credentials.commissionExpirationDate = "2000-01-01"
        var fetches = 0
        let model = CredentialsEditorModel(saved: credentials, fetch: {
            fetches += 1
            throw APIError.serverError("Connection lost")
        })
        await model.reload()
        #expect(model.saved == credentials && model.error == "Connection lost")
        model.edit(CredentialSection.commission.fields[0], value: "Unsaved commission")
        await model.reload()
        #expect(fetches == 1 && model.draft.commissionNumber == "Unsaved commission")
    }

    @Test func accountResetRejectsALateCredentialResponse() async {
        let started = AsyncStream<Void>.makeStream()
        var pending: CheckedContinuation<Credentials, Never>?
        let model = CredentialsEditorModel(fetch: {
            await withCheckedContinuation { pending = $0; started.continuation.yield(()) }
        })
        let load = Task { await model.load() }
        var iterator = started.stream.makeAsyncIterator()
        await iterator.next()
        model.reset()
        var previousAccount = Credentials()
        previousAccount.commissionExpirationDate = "2000-01-01"
        pending?.resume(returning: previousAccount)
        await load.value
        #expect(model.saved == nil && model.draft == Credentials() && !model.isBusy)
    }
}

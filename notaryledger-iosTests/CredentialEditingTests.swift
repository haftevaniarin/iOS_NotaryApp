import Foundation
import Testing
@testable import notaryledger_ios

@MainActor
struct CredentialEditingTests {
    private func field(_ id: String) -> CredentialField {
        CredentialSection.allCases.flatMap(\.fields).first { $0.id == id }!
    }

    @Test func loadingNormalizesDatesAndStateWithoutOverwritingLaterEdits() async {
        var credentials = Credentials()
        credentials.commissionNumber = " CA123 "
        credentials.commissionState = " ca "
        credentials.commissionExpirationDate = "2027-01-31T00:00:00.000Z"
        var fetches = 0
        let model = CredentialsEditorModel(fetch: { fetches += 1; return credentials })
        #expect(!model.canEdit)
        model.edit(field("commissionNumber"), value: "Ignored before load")
        await model.load()
        #expect(model.draft.commissionNumber == "CA123")
        #expect(model.draft.commissionState == "CA")
        #expect(model.draft.commissionExpirationDate == "2027-01-31")
        #expect(model.addedSections == [.commission])
        #expect(!model.canSave)
        model.edit(field("commissionState"), value: "ny")
        await model.load()
        #expect(model.draft.commissionState == "NY")
        #expect(model.saved?.commissionState == "CA")
        #expect(model.canSave)
        #expect(fetches == 1)
    }

    @Test func failedLoadAllowsRetryAndKeepsEditingDisabled() async {
        var fetches = 0
        let model = CredentialsEditorModel(fetch: {
            fetches += 1
            if fetches == 1 { throw APIError.serverError("Try again") }
            return Credentials()
        })
        await model.load()
        #expect(model.saved == nil)
        #expect(!model.isBusy && !model.canEdit && !model.canSave)
        #expect(model.error == "Try again")
        await model.load()
        #expect(model.saved == Credentials())
        #expect(model.canEdit && model.error.isEmpty)
    }

    @Test func invalidDatesMissingExpirationAndInvalidCoverageNeverPersist() async {
        var saves = 0
        let model = CredentialsEditorModel(saved: Credentials(), persist: { saves += 1; return $0 })
        model.edit(field("commissionNumber"), value: "CA123")
        await model.save()
        #expect(model.error.contains("expiration date"))
        model.edit(field("commissionExpirationDate"), value: "2027-02-29")
        await model.save()
        #expect(model.error.contains("valid"))
        model.edit(field("commissionExpirationDate"), value: "2028-02-29")
        model.edit(field("eoExpirationDate"), value: "2028-03-01")
        model.edit(field("eoCoverageAmount"), value: "-1")
        await model.save()
        #expect(model.error.contains("coverage amount"))
        #expect(saves == 0)
        #expect(model.hasChanges && model.saved == Credentials())
    }

    @Test func backgroundExpirationCannotPrecedeCompletion() async {
        var saves = 0
        let model = CredentialsEditorModel(saved: Credentials(), persist: { saves += 1; return $0 })
        model.edit(field("backgroundCheckCompletedDate"), value: "2027-06-02")
        model.edit(field("backgroundCheckExpirationDate"), value: "2027-06-01")
        await model.save()
        #expect(model.error == "Background check expiration must be on or after completion.")
        #expect(saves == 0)
        model.edit(field("backgroundCheckExpirationDate"), value: "2027-06-02")
        await model.save()
        #expect(model.error.isEmpty && saves == 1)
    }

    @Test func failedSavePreservesDraftAndRetryUsesServerResponse() async {
        var credentials = Credentials()
        credentials.commissionNumber = "Original"
        credentials.commissionExpirationDate = "2027-01-31"
        var saves = 0
        let model = CredentialsEditorModel(saved: credentials, persist: { submitted in
            saves += 1
            if saves == 1 { throw APIError.serverError("Connection lost") }
            #expect(submitted.commissionNumber == "Updated")
            var response = submitted
            response.commissionState = "CA"
            return response
        })
        model.edit(field("commissionNumber"), value: " Updated ")
        await model.save()
        #expect(model.error == "Connection lost")
        #expect(model.draft.commissionNumber == " Updated ")
        #expect(model.saved == credentials)
        #expect(model.canSave && model.success.isEmpty)
        await model.save()
        #expect(model.draft.commissionNumber == "Updated")
        #expect(model.draft.commissionState == "CA")
        #expect(model.saved == model.draft)
        #expect(!model.canSave && !model.success.isEmpty && model.error.isEmpty)
        await model.save()
        #expect(saves == 2)
        model.edit(field("commissionNumber"), value: "Another edit")
        #expect(model.success.isEmpty)
    }

    @Test func clearingAnEntireCredentialPersistsNullsAndRemovesItsSummary() async throws {
        var credentials = Credentials()
        credentials.eoProvider = "Example Insurance"
        credentials.eoCoverageAmount = "25000.50"
        credentials.eoExpirationDate = "2027-06-01"
        var submitted: Credentials?
        let model = CredentialsEditorModel(saved: credentials, persist: { submitted = $0; return $0 })
        for field in CredentialSection.insurance.fields { model.edit(field, value: " ") }
        await model.save()
        let payload = try #require(submitted)
        let json = try #require(JSONSerialization.jsonObject(with: payload.requestBody()) as? [String: Any])
        #expect(json["eoProvider"] is NSNull)
        #expect(json["eoCoverageAmount"] is NSNull)
        #expect(json["eoExpirationDate"] is NSNull)
        #expect(model.addedSections.isEmpty && !model.hasChanges)
    }

    @Test func anInFlightSaveBlocksEditingAndDuplicateRequests() async throws {
        var continuation: CheckedContinuation<Credentials, Never>?
        var started: CheckedContinuation<Void, Never>?
        var saves = 0
        let model = CredentialsEditorModel(saved: Credentials(), persist: { _ in
            saves += 1
            return await withCheckedContinuation {
                continuation = $0
                started?.resume()
            }
        })
        model.edit(field("certificationName"), value: "Signing Agent")
        let task = Task { await model.save() }
        await withCheckedContinuation { signal in
            if continuation != nil { signal.resume() } else { started = signal }
        }
        let pending = try #require(continuation)
        #expect(model.isSaving && !model.canEdit && !model.canSave)
        model.edit(field("certificationName"), value: "Ignored during save")
        await model.save()
        #expect(saves == 1)
        #expect(model.draft.certificationName == "Signing Agent")
        pending.resume(returning: model.draft)
        await task.value
        #expect(!model.isBusy && !model.hasChanges)
    }

    @Test func expirationUsesWrittenCalendarDayAcrossTimeZonesAndMonthEnds() throws {
        for zone in ["America/Los_Angeles", "Pacific/Kiritimati", "Europe/London"] {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try #require(TimeZone(identifier: zone))
            let today = try #require(CredentialDates.date("2026-01-31", calendar: calendar))
            #expect(CredentialDates.status("2026-01-30", today: today, calendar: calendar) == .expired)
            #expect(CredentialDates.status("2026-01-31T00:00:00.000Z", today: today, calendar: calendar) == .expiringSoon(days: 0))
            #expect(CredentialDates.status("2026-02-28", today: today, calendar: calendar) == .expiringSoon(days: 28))
            #expect(CredentialDates.status("2026-03-01", today: today, calendar: calendar) == .current)
            #expect(CredentialDates.status("2026-02-29", today: today, calendar: calendar) == .invalid)
            #expect(CredentialDates.status(nil, today: today, calendar: calendar) == .missing)
        }
    }
}

import Foundation
import PDFKit
import Testing
@testable import notaryledger_ios

@MainActor
struct ParityContractTests {
    private let api = APIService(baseURL: "https://api.example.test")

    @Test func timePickerNormalizesClockValuesWithoutChangingTheirMeaning() throws {
        for (input, expected) in [("00:00", "00:00"), ("12:00 AM", "00:00"), ("12:00 PM", "12:00"), ("2:45 PM", "14:45"), (" 10:30 am ", "10:30"), ("23:59", "23:59")] {
            let date = try #require(TimeParser.date(from: input))
            #expect(TimeParser.apiTimeString(from: date) == expected)
            #expect(TimeParser.normalized(input) == expected)
        }
        #expect(TimeParser.normalized(nil).isEmpty)
        #expect(TimeParser.date(from: "24:00") == nil)
        #expect(TimeParser.date(from: "12:60") == nil)
    }

    @Test func selectedTimeIsEncodedOnTheSelectedSigningDay() throws {
        let value = SigningOrderPayload.scheduledDate(date: "2026-11-15", time: TimeParser.normalized("2:45 PM"))
        let scheduled = try #require(DateParser.date(from: value))
        #expect(DateParser.apiDateString(from: scheduled) == "2026-11-15")
        #expect(Calendar.current.component(.hour, from: scheduled) == 14)
        #expect(Calendar.current.component(.minute, from: scheduled) == 45)
    }

    @Test func profileEnvelopeDoesNotDecodeAsAnEmptyUser() throws {
        let json = Data(#"{"success":true,"data":{"user":{"id":"u1","fullName":"Avery Notary","email":"a@example.test","role":"ADMIN","defaultStartAddress":"123 Main St","profilePhotoUrl":"https://photo.example/me.webp","profilePhotoUpload":{"id":"scan-1","status":"SCANNING"}}}}"#.utf8)
        let user = try api.decodeEnvelopeOrDirect(AuthUser.self, from: json)
        #expect(user.id == "u1")
        #expect(user.defaultStartAddress == "123 Main St")
        #expect(user.profilePhotoUpload?.isPending == true)
        #expect(user.canAccessAdminAudit)
        let restored = try JSONDecoder().decode(AuthUser.self, from: JSONEncoder().encode(user))
        #expect(restored == user)
    }

    @Test func onlyExactAdminRoleHasAdminNavigationAccess() {
        #expect(!AuthUser(id: "u", fullName: "A", email: "a", role: "NOT_ADMIN", isAdmin: true).canAccessAdminAudit)
        #expect(!AuthUser(id: "u", fullName: "A", email: "a", role: "NOTARY").canAccessAdminAudit)
        #expect(AuthUser(id: "u", fullName: "A", email: "a", role: "ADMIN").canAccessAdminAudit)
    }

    @Test func profileWithBillingKeepsUserFields() throws {
        let userJSON = Data(#"{"id":"u1","firstName":"Updated","lastName":"Notary","fullName":"Updated Notary","email":"a@example.test","role":"NOTARY","defaultStartAddress":null,"profilePhotoUrl":null,"profilePhotoUpload":null,"billing":{"plan":"FREE","subscriptionStatus":"INACTIVE","lifetimeOrdersCreated":3}}"#.utf8)
        for json in [userJSON, Data(#"{"success":true,"data":{"user":\#(String(decoding: userJSON, as: UTF8.self))}}"#.utf8)] {
            let user = try api.decodeEnvelopeOrDirect(AuthUser.self, from: json)
            #expect(user.id == "u1")
            #expect(user.fullName == "Updated Notary")
            #expect(user.email == "a@example.test")
            #expect(user.defaultStartAddress == nil)
        }
    }

    @Test func credentialsDecodeDecimalCoverageAndClearFieldsWithNull() throws {
        var credentials = try api.decodeEnvelopeOrDirect(Credentials.self, from: Data(#"{"commissionNumber":"CA123","commissionExpirationDate":"2027-01-31T00:00:00.000Z","eoCoverageAmount":"25000.50","backgroundCheckExpirationDate":"2027-06-20"}"#.utf8))
        #expect(credentials.eoCoverageAmount == "25000.50")
        credentials.commissionNumber = nil
        let json = try #require(JSONSerialization.jsonObject(with: credentials.requestBody()) as? [String: Any])
        #expect(json["commissionNumber"] is NSNull)
        #expect(json["eoCoverageAmount"] as? Double == 25000.50)
        #expect(json["commissionExpiration"] == nil)
        #expect(json["bondExpiration"] == nil)
    }

    @Test func expiryUsesCalendarMonthAndIncludesToday() throws {
        let today = try #require(DateParser.date(from: "2026-02-01"))
        #expect(CredentialsEditor.expirationStatus("2026-01-31", today: today) == "Expired")
        #expect(CredentialsEditor.expirationStatus("2026-02-01", today: today) == "Expires in 0 days")
        #expect(CredentialsEditor.expirationStatus("2026-03-01", today: today) != "Current")
        #expect(CredentialsEditor.expirationStatus("2026-03-02", today: today) == "Current")
    }

    @Test func billingAndCheckoutUnwrapTheirNamedEnvelopes() throws {
        let billing = try api.decodeEnvelopeOrDirect(BillingStatusPayload.self, from: Data(#"{"success":true,"data":{"billing":{"plan":"PRO","isPro":true,"subscriptionStatus":"ACTIVE","features":{"invoiceGeneration":true}}}}"#.utf8))
        #expect(billing.isPro == true)
        #expect(billing.features?["invoiceGeneration"] == true)
        let checkout = try api.decodeEnvelopeOrDirect(BillingSession.self, from: Data(#"{"success":true,"data":{"checkoutSession":{"id":"cs_1","url":"https://checkout.stripe.com/1"}}}"#.utf8))
        #expect(checkout.sessionId == "cs_1")
    }

    @Test func cardUpdatesClearPrivateFieldsAndExcludeServerOwnedFields() throws {
        var card = BusinessCard()
        card.slug = "avery-notary"
        card.displayName = "Avery"
        card.businessPhone = nil
        card.isPublished = true
        card.canonicalUrl = "https://notaryledger.org/card/avery-notary"
        let json = try #require(JSONSerialization.jsonObject(with: card.updateBody()) as? [String: Any])
        #expect(json["businessPhone"] is NSNull)
        #expect(json["showBusinessPhone"] as? Bool == false)
        #expect(json["useProfilePhoto"] as? Bool == false)
        #expect(json["isPublished"] == nil)
        #expect(json["canonicalUrl"] == nil)
    }

    @Test func orderDecodesStructuredMileageAndTimestamp() throws {
        let order = try api.decodeEnvelopeOrDirect(SigningOrder.self, from: Data(#"{"id":"o1","date":"2026-11-01T18:30:00.000Z","fee":"150.25","paymentStatus":"Pending","mileage":{"businessMiles":24.5,"oneWayMiles":12.25,"roundTripMiles":24.5,"parkingFee":5.75,"tripType":"round-trip","mileageEntryMode":"CALCULATED","tripStartAddress":"123 Main"}}"#.utf8))
        #expect(order.mileage == 24.5)
        #expect(order.travelFee == 5.75)
        #expect(order.mileageDetails?.entryMode == "CALCULATED")
        #expect(order.time != nil)
        #expect(DateParser.date(from: order.date) != nil)
    }

    @Test func mileageClearExplicitlyEncodesNullUsingBackendNames() throws {
        let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(MileagePayload(mileage: nil, travelFee: nil))) as? [String: Any])
        #expect(json["miles"] is NSNull)
        #expect(json["parkingFee"] is NSNull)
        #expect(json["travelFee"] == nil)
    }

    @Test func taxSummaryMapsAuthoritativeTotals() throws {
        let report = try api.decodeEnvelopeOrDirect(BackendTaxSummary.self, from: Data(#"{"taxYear":2026,"totals":{"totalIncomeReceived":1000,"unpaidIncome":100,"totalNotarialActExemptFees":100,"businessExpenses":200,"totalTravelExpenses":30,"totalBusinessMiles":123,"netSelfEmploymentIncome":700,"seTaxableIncome":646.45,"estimatedSelfEmploymentTax":98.91,"estimatedTaxPayments":50},"paidOrders":[],"unpaidOrders":[]}"#.utf8))
        let summary = report.summary(year: 2026)
        #expect(summary.incomeReceived == 1000)
        #expect(summary.totalBusinessMiles == 123)
        #expect(summary.travelExpenses == 30)
        #expect(summary.selfEmploymentTaxableIncome == 646.45)
    }

    @Test func auditPaginationAndDeletionStatusPreserveTheirWrappers() throws {
        let audit = try api.decodeEnvelopeOrDirect(AuditPage.self, from: Data(#"{"success":true,"data":{"items":[{"id":"a1","action":"LOGIN_SUCCEEDED","outcome":"SUCCESS","severity":"INFO","createdAt":"2026-11-01T00:00:00Z"}],"pagination":{"page":2,"pageSize":25,"total":50}}}"#.utf8))
        #expect(audit.items.first?.action == "LOGIN_SUCCEEDED")
        #expect(audit.pagination.page == 2)
        let deletion = try api.decodeEnvelopeOrDirect(DeletionStatus.self, from: Data(#"{"success":true,"data":{"deletionRequest":{"id":"d1","status":"IN_REVIEW","requestedAt":"2026-11-01","scheduledDeletionAt":"2026-12-01"}}}"#.utf8))
        #expect(deletion.deletionRequest?.isActive == true)
    }

    @Test func photoValidationRejectsUnsupportedAndOversizeInput() throws {
        #expect(throws: APIError.self) { try UploadValidation.validate(data: Data([1]), mimeType: "image/heic", photo: true) }
        #expect(throws: APIError.self) { try UploadValidation.validate(data: Data(repeating: 1, count: 5 * 1024 * 1024 + 1), mimeType: "image/jpeg", photo: true) }
        try UploadValidation.validate(data: Data([1]), mimeType: "image/png", photo: true)
        #expect(throws: (any Error).self) { try api.decodeEnvelopeOrDirect(PhotoResponse.self, from: Data(#"{"success":true,"data":{}}"#.utf8)) }
    }

    @Test func extractionDoesNotRequireInventedSavedOrderFields() throws {
        let draft = try api.decodeEnvelopeOrDirect(ExtractedSigning.self, from: Data(#"{"success":true,"data":{"draft":{"customerName":"Acme","signerName":null,"date":null,"fee":null,"time":"13:45"},"confidence":{"customerName":0.9}}}"#.utf8))
        #expect(draft.customerName == "Acme")
        #expect(draft.signerName == nil)
        #expect(draft.fee == nil)
    }

    @Test func pdfExportsAreValidAndPaginate() throws {
        let data = LedgerPDF.document(title: "Test Export", lines: (1...100).map { "Ledger line \($0)" })
        let pdf = try #require(PDFDocument(data: data))
        #expect(pdf.pageCount > 1)
        #expect(pdf.string?.contains("Ledger line 100") == true)
    }
    @Test func cardValidationMatchesPrivacyAndURLRules() {
        var card = BusinessCard()
        card.slug = "admin"
        #expect(card.validationMessage() != nil)
        card.slug = "avery-notary"
        card.instagramUrl = "https://evil.example/instagram"
        #expect(card.validationMessage() != nil)
        card.instagramUrl = "https://www.instagram.com/avery"
        card.profilePhotoUrl = "http://photos.example/me.jpg"
        #expect(card.validationMessage() != nil)
        card.profilePhotoUrl = nil
        card.businessPhone = "(818) 555-1234"
        #expect(card.validationMessage() == nil)
    }

    @Test func ordinaryOrderEditsPreserveStructuredMileageAndUseSupportedKeys() throws {
        var payload = SigningOrderPayload(customerName: "Acme", payerName: nil, signerName: "Avery", signingType: "Loan Signing", date: "2026-11-01", time: "13:45", fee: 100, notarialActFee: 10, paid: false, paidDate: nil, invoiceNumber: "INV-1", notes: nil, mileage: 24, travelFee: 10, status: .pending)
        payload.preserveMileage = true
        let json = try #require(JSONSerialization.jsonObject(with: api.encodedBody(payload)) as? [String: Any])
        #expect(json["miles"] == nil)
        #expect(json["oneWayMiles"] == nil)
        #expect(json["parkingFee"] == nil)
        #expect(json["time"] == nil)
        #expect(json["status"] == nil)
        #expect(json["paymentStatus"] as? String == "Pending")
        #expect((json["date"] as? String)?.contains("T") == true)
    }

    @Test func estimatedTaxPaymentDecodesDecimalAmount() throws {
        let payment = try api.decodeEnvelopeOrDirect(EstimatedTaxPayment.self, from: Data(#"{"id":"p1","date":"2026-11-01T00:00:00.000Z","amount":"125.50","quarter":"Q4","taxYear":2026}"#.utf8))
        #expect(payment.amount == 125.50)
        #expect(payment.taxYear == 2026)
    }

    @Test func receiptExtractionUnwrapsDraftAndConfidence() throws {
        let draft = try api.decodeEnvelopeOrDirect(ExtractedExpense.self, from: Data(#"{"success":true,"data":{"draft":{"description":"Office Depot","date":"2026-11-01","amount":12.50,"category":"Office supplies","businessUsePercent":100},"confidence":{"amount":0.99}}}"#.utf8))
        #expect(draft.description == "Office Depot")
        #expect(draft.amount == 12.50)
    }

    @Test func spreadsheetImportRetainsCountsAndSavedOrders() throws {
        let result = try api.decodeEnvelopeOrDirect(SigningImportResult.self, from: Data(#"{"success":true,"data":{"importedCount":1,"skippedDuplicateCount":2,"skippedDuplicates":[],"orders":[{"id":"imported-1","customerName":"Acme","signerName":"Avery","date":"2026-11-01","fee":"125.50","paid":false}]}}"#.utf8))
        #expect(result.importedCount == 1)
        #expect(result.skippedDuplicateCount == 2)
        #expect(result.orders.first?.fee == 125.50)
        let message = APIService.normalizedErrorMessage(from: Data(#"{"success":false,"error":{"code":"ORDER_IMPORT_VALIDATION_FAILED","message":"Invalid rows","rows":[{"row":3,"message":"Missing signer"}]}}"#.utf8))
        #expect(message == "Row 3: Missing signer")
    }

}

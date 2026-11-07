import Foundation
import Testing
import UIKit
@testable import notaryledger_ios

@MainActor
struct ScreenshotOrderImportTests {
    private func extract(_ text: String, confidence: Float = 1) throws -> ScreenshotOrderDraft {
        try ScreenshotOrderExtractor.extract([ScreenshotTextLine(text: text, confidence: confidence)])
    }

    @Test func mapsLabeledDetailsWithoutAssumingAFieldOrder() throws {
        let draft = try extract("""
        Notary fee: $150.00
        Signing date: 2027-01-15
        Signing time: 2:30 PM
        Title company: Acme Title
        Contact name: Alex Lee
        Contact phone: 555-0100
        Contact email: alex@example.test
        Order #: ABC-123
        Signer: Jamie Smith
        Phone: 555-0101
        Email: jamie@example.test
        Signing location: 12 Main St
        Suite 2, Austin TX 78701
        Appointment type: Refinance
        Document type: Loan package
        Special instructions: Call before arrival
        Bring two copies
        """)
        #expect(draft[.reference] == "ABC-123")
        #expect(draft[.company] == "Acme Title")
        #expect(draft[.date] == "2027-01-15")
        #expect(draft[.time] == "14:30")
        #expect(draft[.fee] == "150.00")
        #expect(draft[.contactEmail] == "alex@example.test")
        #expect(draft[.signerEmail] == "jamie@example.test")
        #expect(draft[.location] == "12 Main St\nSuite 2, Austin TX 78701")
        #expect(draft.mappedNotes.contains("Order reference: ABC-123"))
        #expect(draft.mappedNotes.contains("Document type: Loan package"))
        #expect(draft.mappedNotes.contains("Bring two copies"))
        #expect(draft[.appointmentType] == "Refinance")
        #expect(draft.formFields.customerName == "Acme Title")
        #expect(draft.formFields.signerName == "Jamie Smith")
        #expect(draft.formFields.signingType == "Refinance")
        #expect(draft.formFields.date == "2027-01-15")
        #expect(draft.formFields.time == "14:30")
        #expect(draft.formFields.fee == "150.00")
        #expect(draft.formFields.invoiceNumber.isEmpty)
        #expect(draft.formFields.payerName.isEmpty)
    }

    @Test func supportsStackedLabelsMultipleSignersAndLowConfidence() throws {
        let draft = try extract("Title company\nAcme Title\nSigner: Jamie Smith\nSigner: Taylor Smith\nOrder number: 42", confidence: 0.6)
        #expect(draft[.company] == "Acme Title")
        #expect(draft[.signer] == "Jamie Smith\nTaylor Smith")
        #expect(draft.warnings[.company] != nil)
        #expect(draft[.date].isEmpty)
        #expect(draft[.fee].isEmpty)
        #expect(draft[.appointmentType].isEmpty)
    }

    @Test func ambiguousValuesStayBlankWithOriginalEvidence() throws {
        let draft = try extract("Date: 03/04/2027\nTime: 9:00\nFee: $100 or $150\nCompany: Acme")
        for field in [ScreenshotOrderField.date, .time, .fee] {
            #expect(draft[field].isEmpty)
            #expect(draft.warnings[field] != nil)
            #expect(draft.evidence[field]?.isEmpty == false)
        }
        #expect(ScreenshotOrderExtractor.normalizedDate("February 30, 2027") == nil)
        #expect(ScreenshotOrderExtractor.normalizedDate("tomorrow") == nil)
        #expect(ScreenshotOrderExtractor.normalizedDate("2027-02-28") == "2027-02-28")
        #expect(ScreenshotOrderExtractor.normalizedDate("January 15, 2027") == "2027-01-15")
        #expect(ScreenshotOrderExtractor.normalizedDate("01/15/2027") == "2027-01-15")
        #expect(ScreenshotOrderExtractor.normalizedTime("14:00") == "14:00")
        #expect(ScreenshotOrderExtractor.normalizedTime("2 PM EST") == nil)
        #expect(ScreenshotOrderExtractor.normalizedFee("€150") == nil)
        #expect(ScreenshotOrderExtractor.normalizedFee("$1,250.50") == "1250.50")
    }

    @Test func conflictingCandidatesDoNotSilentlyChooseAValue() throws {
        let draft = try extract("Signing date: 2027-01-15\nAppointment date: 2027-01-16\nFee: $100\nNotary fee: $200")
        #expect(draft[.date].isEmpty)
        #expect(draft[.fee].isEmpty)
        #expect(draft.warnings.count == 2)
    }

    @Test func supportsSeveralLabeledFieldsOnTheSameRow() throws {
        let draft = try extract("Signer: Jamie Smith Date: 2027-01-15\nCompany: Acme Title Fee: $150")
        #expect(draft[.signer] == "Jamie Smith")
        #expect(draft[.date] == "2027-01-15")
        #expect(draft[.company] == "Acme Title")
        #expect(draft[.fee] == "150")
    }

    @Test func unavailableAndMalformedContactValuesRemainBlank() throws {
        let draft = try extract("Company: Acme Title\nSigner: N/A\nContact name: Not provided\nContact email: alex at example.test\nContact phone: 123\nDocument type: TBD")
        for field in [ScreenshotOrderField.signer, .contactName, .contactEmail, .contactPhone, .documentType] {
            #expect(draft[field].isEmpty)
        }
        #expect(draft.warnings[.contactEmail] != nil)
        #expect(draft.warnings[.contactPhone] != nil)
    }

    @Test func explicitCompanyContactLabelsKeepTheirOwnerAfterTheSigner() throws {
        let draft = try extract("Signer: Jamie Smith\nContact phone: 555-0100\nContact email: alex@example.test\nSigner phone: 555-0101")
        #expect(draft[.contactPhone] == "555-0100")
        #expect(draft[.contactEmail] == "alex@example.test")
        #expect(draft[.signerPhone] == "555-0101")
    }

    @Test func emptyAndUnrelatedScreenshotsHaveDifferentErrors() {
        #expect(throws: ScreenshotImportError.self) { try extract("") }
        #expect(throws: ScreenshotImportError.self) { try extract("Welcome to your photo library") }
    }

    @Test func reviewAndAmbiguousValueConfirmationAreRequired() {
        let errors = ScreenshotImportValidation.errors(date: "", time: "14:00", confirmedDate: false,
                                                       confirmedTime: false, confirmedFee: false, confirmedReview: false)
        #expect(Set(errors.keys) == ["date", "time", "fee", "review"])
        #expect(ScreenshotImportValidation.errors(date: "2027-01-15", time: "", confirmedDate: true,
                                                confirmedTime: false, confirmedFee: true, confirmedReview: true).isEmpty)
        #expect(ScreenshotImportValidation.errors(date: "2027-02-30", time: "", confirmedDate: true,
                                                confirmedTime: true, confirmedFee: true, confirmedReview: true)["date"] != nil)
        #expect(ScreenshotImportValidation.errors(date: "2027-01-15", time: "", confirmedDate: true,
                                                confirmedTime: false, confirmedFee: true, confirmedReview: true,
                                                requiresTimeConfirmation: true)["time"] != nil)
    }

    @Test func duplicatesMatchReferenceOrAllThreeScheduleFields() {
        let orders = [
            SigningOrder(id: "ref", customerName: "A", signerName: "Someone Else", date: "2027-01-01", fee: 100, paid: false, invoiceNumber: "INV-1", notes: "Order reference: ABC-123"),
            SigningOrder(id: "schedule", customerName: "B", signerName: "Jamie Smith", date: "2027-01-15T14:00:00Z", fee: 100, paid: false, notes: "Signing location: 12 Main St, Austin TX")
        ]
        #expect(ScreenshotDuplicateDetection.matches(reference: "abc-123", signer: "", date: "", location: "", orders: orders).map(\.id) == ["ref"])
        #expect(ScreenshotDuplicateDetection.matches(reference: "ABC123", signer: "", date: "", location: "", orders: orders).map(\.id) == ["ref"])
        #expect(ScreenshotDuplicateDetection.matches(reference: "", signer: " JAMIE SMITH ", date: "2027-01-15", location: "12 Main St Austin TX", orders: orders).map(\.id) == ["schedule"])
        #expect(ScreenshotDuplicateDetection.matches(reference: "", signer: "Jamie Smith", date: "2027-01-15", location: "", orders: orders).isEmpty)
        #expect(ScreenshotDuplicateDetection.matches(reference: "", signer: "Jamie Smith", date: "2027-01-16", location: "12 Main St Austin TX", orders: orders).isEmpty)
        #expect(ScreenshotDuplicateDetection.matches(reference: "", signer: "", date: "", location: "", orders: orders).isEmpty)
        #expect(ScreenshotDuplicateDetection.matches(notes: "Order reference: ABC-123", signer: "", date: "", orders: orders).map(\.id) == ["ref"])
    }

    @Test func duplicateDatesUseTheSameLocalCalendarAsOrderSaving() {
        let order = SigningOrder(id: "late", customerName: "A", signerName: "Jamie Smith",
                                 date: SigningOrderPayload.scheduledDate(date: "2027-01-15", time: "23:00"),
                                 fee: 100, paid: false, notes: "Signing location: 12 Main St\nAustin TX")
        #expect(ScreenshotDuplicateDetection.matches(reference: "", signer: "Jamie Smith", date: "2027-01-15",
                                                    location: "12 Main St Austin TX", orders: [order]).map(\.id) == ["late"])
    }

    @Test func mappingDoesNotTruncateNotesToMeetBackendLimit() throws {
        let draft = try extract("Company: Acme Title\nSpecial instructions: " + String(repeating: "x", count: 300))
        #expect(draft.mappedNotes.utf16.count > 255)
        #expect(OrderFormValidation.errors(customerName: "A", signerName: "B", fee: "100", notarialActFee: "", invoiceNumber: "I1", notes: draft.mappedNotes, time: "", mileage: "", travelFee: "")["notes"] != nil)
    }

    @Test func visionRecognizesAnActualScreenshotOnDevice() async throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1000, height: 700)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1000, height: 700))
            let lines = ["Title company: Acme Title", "Order number: ABC-123", "Signer name: Jamie Smith", "Notary fee: $150.00", "Signing date: 2027-01-15"]
            for (index, line) in lines.enumerated() {
                (line as NSString).draw(at: CGPoint(x: 40, y: 40 + index * 100), withAttributes: [.font: UIFont.systemFont(ofSize: 38), .foregroundColor: UIColor.black])
            }
        }
        let draft = try await ScreenshotTextRecognition.recognize(#require(image.pngData()))
        #expect(draft[.company] == "Acme Title")
        #expect(draft[.reference] == "ABC-123")
        #expect(draft[.signer] == "Jamie Smith")
        #expect(draft[.fee] == "150.00")
        #expect(draft[.date] == "2027-01-15")
    }
}

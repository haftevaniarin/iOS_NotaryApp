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

    @Test(arguments: [
        ("Buyer Only 1st Only", "Loan Signing"), ("Purchase Closing", "Loan Signing"),
        ("Seller Only", "Seller Package"), ("Seller Package", "Seller Package"),
        ("Cash-Out Refinance", "Refinance"), ("Loan Signing - Refinance", "Refinance"),
        ("Home Equity Line of Credit", "HELOC"), ("HELOC Signing", "HELOC"),
        ("GNW", "General Notary"), ("General Notary Work", "General Notary"), ("Other", "Other")
    ])
    func extractedSigningTypeSelectsAnExistingOption(source: String, expected: String) throws {
        let draft = try extract("Signing type: \(source)")
        #expect(draft[.appointmentType] == expected)
        #expect(draft.formFields.signingType == expected)
        #expect(SigningTypeOptions.values.contains(draft.formFields.signingType))
        #expect(draft.evidence[.appointmentType] == source)
        if source != expected { #expect(draft.mappedNotes.contains("Screenshot signing type: \(source)")) }
    }

    @Test func ambiguousOrUnknownTypesRequireASelectionAndMissingTypesStayBlank() throws {
        for source in ["Refinance / HELOC", "Buyer / Seller", "Inspection", "Signing type pending"] {
            let draft = try extract("Signing type: \(source)")
            #expect(draft.formFields.signingType.isEmpty)
            #expect(draft.warnings[.appointmentType] != nil)
            #expect(draft.mappedNotes.contains(source))
            let errors = ScreenshotImportValidation.errors(date: "2026-09-11", time: "12:00", confirmedDate: true,
                                                           confirmedTime: true, confirmedFee: true, confirmedReview: true,
                                                           signingType: draft.formFields.signingType, requiresSigningType: true)
            #expect(errors["signingType"] != nil)
        }
        let missing = try extract("Company: Acme Title")
        #expect(missing.formFields.signingType.isEmpty)
        #expect(missing.evidence[.appointmentType] == nil)
        for type in SigningTypeOptions.values {
            #expect(ScreenshotImportValidation.errors(date: "2026-09-11", time: "", confirmedDate: true,
                                                     confirmedTime: true, confirmedFee: true, confirmedReview: true,
                                                     signingType: type, requiresSigningType: true).isEmpty)
        }
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

    @Test(arguments: ["DATE & TIME", "Date and Time", "Date/Time", "Signing Date & Time", "Appointment Date and Time"])
    func combinedAppointmentLabelExtractsDateTimeAndWrappedTimeZone(label: String) throws {
        let draft = try ScreenshotOrderExtractor.extract([ScreenshotTextLine(text: """
        SIGNER
        Jamie Example
        SIGNING TYPE
        Buyer Only
        \(label)
        September 11, 2026 at 12:00 PM
        (PDT)
        LOCATION
        123 Example St
        NOTARY FEE
        100.00
        """)], localTimeZone: #require(TimeZone(identifier: "America/Los_Angeles")))
        #expect(draft[.date] == "2026-09-11")
        #expect(draft[.time] == "12:00")
        #expect(draft[.signer] == "Jamie Example")
        #expect(draft[.location] == "123 Example St")
        #expect(draft[.fee] == "100.00")
        #expect(draft.formFields.signingType == "Loan Signing")
        #expect(draft.warnings[.date] == nil)
        #expect(draft.warnings[.time] == nil)
        #expect(draft.evidence[.date]?.contains("(PDT)") == true)
        #expect(draft.scheduleExplanation?.contains("America/Los_Angeles") == true)
    }

    @Test func combinedDateTimeSupportsInlineAndSeparateDateAndClockLines() throws {
        for text in [
            "Date & Time: September 11, 2026 at 12:00 PM",
            "Date & Time\nSeptember 11, 2026\n12:00 PM",
            "Signing date: September 11, 2026 at 12:00 PM"
        ] {
            let draft = try extract(text)
            #expect(draft[.date] == "2026-09-11")
            #expect(draft[.time] == "12:00")
        }
    }

    @Test func explicitTimeZoneConversionUsesAppointmentDateAndHandlesDateRollover() throws {
        let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let pacific = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let text = "Date & Time: September 11, 2026 at 11:30 PM (PDT)"
        let draft = try ScreenshotOrderExtractor.extract([ScreenshotTextLine(text: text)], localTimeZone: tokyo)
        #expect(draft[.date] == "2026-09-12")
        #expect(draft[.time] == "15:30")
        // PST is a printed fixed offset; September in Los Angeles is still daylight time.
        let standard = try ScreenshotOrderExtractor.extract([ScreenshotTextLine(text: "Date/Time: September 11, 2026 at 12:00 PM (PST)")], localTimeZone: pacific)
        #expect(standard[.date] == "2026-09-11")
        #expect(standard[.time] == "13:00")
        let utc = try ScreenshotOrderExtractor.extract([ScreenshotTextLine(text: "Date & Time: September 11, 2026 at 11:30 PM (UTC-07:00)")], localTimeZone: tokyo)
        #expect(utc[.date] == draft[.date])
        #expect(utc[.time] == draft[.time])
    }

    @Test func combinedAppointmentKeepsAmbiguousValuesBlankAndRequiresConfirmation() throws {
        for text in [
            "Date & Time: 03/04/2027 at 12:00 PM (PDT)",
            "Date & Time: September 11, 2026 at 12:00 PM (CST)",
            "Date & Time: February 30, 2027 at 12:00 PM (PDT)"
        ] {
            let draft = try extract(text)
            #expect(draft[.date].isEmpty)
            #expect(draft[.time].isEmpty)
            #expect(draft.warnings[.date] != nil)
            #expect(draft.warnings[.time] != nil)
        }
        let draft = try extract("Date & Time: September 11, 2026 at 12:00 PM\nFee: 100")
        let errors = ScreenshotImportValidation.errors(date: draft[.date], time: draft[.time], confirmedDate: false,
                                                       confirmedTime: false, confirmedFee: true, confirmedReview: true)
        #expect(errors["date"] != nil)
        #expect(errors["time"] != nil)
    }

    @Test func wrappedTimeZoneConfidenceAppliesToBothAppointmentFields() throws {
        let draft = try ScreenshotOrderExtractor.extract([
            ScreenshotTextLine(text: "DATE & TIME"),
            ScreenshotTextLine(text: "September 11, 2026 at 12:00 PM"),
            ScreenshotTextLine(text: "(PDT)", confidence: 0.5)
        ])
        #expect(!draft[.date].isEmpty)
        #expect(!draft[.time].isEmpty)
        #expect(draft.warnings[.date] != nil)
        #expect(draft.warnings[.time] != nil)
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

    @Test func visionRecognizesStackedDateAndTimeOnADarkAssignmentCard() async throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1000, height: 1000)).image { context in
            UIColor(white: 0.12, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1000, height: 1000))
            let lines = ["SIGNER", "Jamie Example", "SIGNING TYPE", "Buyer Only", "DATE & TIME", "September 11, 2026 at 12:00 PM", "(PDT)", "NOTARY FEE", "100.00"]
            for (index, line) in lines.enumerated() {
                (line as NSString).draw(at: CGPoint(x: 50, y: 50 + index * 100), withAttributes: [.font: UIFont.systemFont(ofSize: 38), .foregroundColor: UIColor.white])
            }
        }
        let draft = try await ScreenshotTextRecognition.recognize(#require(image.pngData()))
        #expect(!draft[.date].isEmpty)
        #expect(!draft[.time].isEmpty)
        #expect(draft.evidence[.date]?.contains("September 11, 2026") == true)
        #expect(draft.scheduleExplanation?.contains("PDT") == true)
        let expected = try #require(ScreenshotAppointmentParser.parse("September 11, 2026 at 12:00 PM (PDT)", localTimeZone: .current))
        #expect(draft[.date] == expected.date)
        #expect(draft[.time] == expected.time)
    }
}

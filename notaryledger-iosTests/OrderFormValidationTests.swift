import Foundation
import Testing
@testable import notaryledger_ios

@MainActor
struct OrderFormValidationTests {
    private func errors(customer: String = "Acme Title", signer: String = "Jamie Smith", fee: String = "150",
                        notarial: String = "", invoice: String = "INV-1", notes: String = "", time: String = "",
                        mileage: String = "", parking: String = "") -> [String: String] {
        OrderFormValidation.errors(customerName: customer, signerName: signer, fee: fee, notarialActFee: notarial,
                                   invoiceNumber: invoice, notes: notes, time: time, mileage: mileage, travelFee: parking)
    }

    @Test func emptyRequiredFieldsAreReportedTogetherWithWebCopy() {
        #expect(errors(customer: "  ", signer: "", fee: "", invoice: " ") == [
            "customerName": "Please enter customer name.", "signerName": "Please enter signer name.",
            "fee": "Please enter a valid fee.", "invoiceNumber": "Please enter invoice number."
        ])
    }

    @Test func invalidAmountsAndTravelValuesStayAttachedToTheirFields() {
        let result = errors(fee: "nan", notarial: "-1", mileage: "invalid", parking: "inf")
        #expect(Set(result.keys) == Set(["fee", "notarialActFee", "mileage", "travelFee"]))
        #expect(result["fee"] == "Please enter a valid fee.")
        #expect(result["notarialActFee"] == "Please enter a valid notarial act fee.")
        #expect(errors(fee: "0", notarial: "0", mileage: "0", parking: "0").isEmpty)
        #expect(errors(notarial: "  ", mileage: " ", parking: " ").isEmpty)
    }

    @Test func notarialPortionCannotExceedTheTotalFee() {
        #expect(errors(notarial: "150.01")["notarialActFee"] == "Notarial act fee cannot exceed the total fee.")
        #expect(errors(notarial: "150").isEmpty)
        #expect(errors(fee: "-1")["fee"] == "Please enter a valid fee.")
    }

    @Test func notesUseWebCharacterLimitAndTimeUsesTwentyFourHourClock() {
        #expect(errors(notes: String(repeating: "a", count: 255), time: "23:59").isEmpty)
        #expect(errors(notes: String(repeating: "a", count: 256))["notes"] == "Notes must be 255 characters or fewer.")
        #expect(errors(notes: String(repeating: "😀", count: 128))["notes"] != nil)
        #expect(errors(time: "24:00")["time"] == "Enter time as HH:mm (24-hour).")
    }

    @Test func backendFieldAliasesAndPlainValidationMessagesMapToVisibleControls() throws {
        let response = Data(#"{"error":{"message":"Please review signing details.","details":[{"field":"mileage.parkingFee","message":"Invalid parking."},{"path":"mileage.businessMiles","message":"Invalid miles."},{"name":"paymentStatus","error":"Invalid status."}]}}"#.utf8)
        let error = try #require(OrderValidationFailure.fromResponse(response))
        #expect(error.fieldErrors == ["travelFee": "Invalid parking.", "mileage": "Invalid miles.", "status": "Invalid status."])
        let plain = try #require(OrderValidationFailure.fromResponse(Data(#"{"message":"customerName is too long."}"#.utf8)))
        #expect(plain.fieldErrors == ["customerName": "customerName is too long."])
        #expect(OrderValidationFailure.fromResponse(Data(#"{"message":"Service temporarily unavailable."}"#.utf8)) == nil)
    }
}

extension ValidationAndAPITests {
    @Test func orderCreateAndUpdateKeepServerFieldErrorsForInlineDisplay() async throws {
        let previousToken = SessionStorage.getAccessToken()
        SessionStorage.saveAccessToken("order-validation-fixture")
        defer {
            MockURLProtocol.requestHandler = nil
            MockURLProtocol.requests = []
            if let previousToken { SessionStorage.saveAccessToken(previousToken) } else { SessionStorage.clearTokens() }
        }
        let payload = SigningOrderPayload(customerName: "Acme", payerName: nil, signerName: "Jamie", signingType: nil,
                                         date: "2026-11-05", time: nil, fee: 150, notarialActFee: 0, paid: false,
                                         paidDate: nil, invoiceNumber: "INV-1", notes: nil, mileage: nil, travelFee: nil, status: .pending)
        for (status, response) in [
            (400, #"{"error":{"message":"Invalid signing.","fieldErrors":{"invoiceNumber":["Invoice already exists."],"mileage.miles":"Invalid mileage."}}}"#),
            (422, #"{"message":"Invalid signing.","errors":[{"path":"invoiceNumber","message":"Invoice already exists."},{"field":"miles","message":"Invalid mileage."}]}"#),
            (409, #"{"message":"Invalid signing.","fields":{"invoiceNumber":"Invoice already exists.","miles":"Invalid mileage."}}"#)
        ] {
            MockURLProtocol.requestHandler = { request in
                if request.url?.path == "/api/config/maintenance" {
                    return MockURLProtocol.jsonResponse(for: request, body: #"{"enabled":false}"#)
                }
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer order-validation-fixture")
                return MockURLProtocol.jsonResponse(for: request, statusCode: status, body: response)
            }
            let api = APIService(baseURL: "https://order-validation.example.test", session: MockURLProtocol.session())
            for updating in [false, true] {
                do {
                    if updating { _ = try await api.updateOrder(orderId: "order-1", order: payload) }
                    else { _ = try await api.createOrder(payload) }
                    Issue.record("Invalid orders must not be saved")
                } catch let failure as OrderValidationFailure {
                    #expect(failure.message == "Invalid signing.")
                    #expect(failure.fieldErrors == ["invoiceNumber": "Invoice already exists.", "mileage": "Invalid mileage."])
                }
            }
        }
    }
}

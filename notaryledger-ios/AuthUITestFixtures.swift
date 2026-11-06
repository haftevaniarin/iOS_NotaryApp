#if DEBUG
import Foundation

// Activated only by UI-test launch arguments. Every request is intercepted so
// signup, recovery, and session tests never reach a live account or service.
final class AuthUITestFixtures: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        do {
            var body = request.httpBody
            if body == nil, let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var data = Data()
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }
                    data.append(buffer, count: count)
                }
                body = data
            }
            let object = (body.flatMap { try? JSONSerialization.jsonObject(with: $0) }) as? [String: Any] ?? [:]
            let payload = object.compactMapValues { $0 as? String }
            let path = request.url?.path ?? ""
            var status = 200
            let responseBody: String
            let user = #"{"id":"auth-fixture-user","firstName":"Avery","lastName":"Notary","fullName":"Avery Notary","email":"avery@example.test","role":"NOTARY"}"#
            switch path {
            case "/api/config/maintenance": responseBody = #"{"enabled":false}"#
            case "/api/auth/refresh": status = 401; responseBody = #"{"message":"Session expired."}"#
            case "/api/auth/register":
                if payload["email"] == "exists@example.test" {
                    status = 409; responseBody = #"{"error":{"code":"EMAIL_ALREADY_EXISTS","message":"An account with this email already exists."}}"#
                } else if payload["email"] == "immediate@example.test" {
                    responseBody = #"{"accessToken":"fixture-access","refreshToken":"fixture-refresh","user":\#(user)}"#
                } else {
                    responseBody = #"{"success":true,"data":{"emailVerificationRequired":true,"message":"Check your email to verify your account, then sign in."}}"#
                }
            case "/api/auth/login":
                if payload["password"] != "StrongPass12!" {
                    status = 401; responseBody = #"{"error":{"code":"INVALID_CREDENTIALS","message":"Invalid email or password."}}"#
                } else { responseBody = #"{"accessToken":"fixture-access","refreshToken":"fixture-refresh","user":\#(user)}"# }
            case "/api/auth/forgot-password", "/api/auth/logout": responseBody = "{}"
            case "/api/support/contact": responseBody = #"{"success":true,"message":"Support request sent."}"#
            case "/api/auth/reset-password":
                if payload["token"] == "expired" { status = 400; responseBody = #"{"message":"Invalid or expired reset link."}"# }
                else { responseBody = "{}" }
            case "/api/auth/verify-email":
                if payload["token"] == "offline" { throw URLError(.notConnectedToInternet) }
                if payload["token"] == "server-error" { status = 503; responseBody = #"{"message":"Unavailable."}"# }
                else if payload["token"] == "valid" { responseBody = "{}" }
                else { status = 400; responseBody = #"{"message":"Verification link expired."}"# }
            case "/api/auth/me": responseBody = user
            case "/api/orders":
                if request.httpMethod == "POST" {
                    if payload["invoiceNumber"] == "SERVER-ERROR" {
                        status = 400
                        responseBody = #"{"error":{"message":"Please review signing details.","details":[{"field":"invoiceNumber","message":"Invoice number is already in use."},{"field":"mileage.parkingFee","message":"Parking fee must be zero or greater."}]}}"#
                    } else {
                        var saved = object
                        saved["id"] = "new-signing-fixture"
                        responseBody = String(decoding: try JSONSerialization.data(withJSONObject: saved), as: UTF8.self)
                    }
                } else {
                    responseBody = ProcessInfo.processInfo.arguments.contains("--customer-invoice-fixtures")
                        ? #"[{"id":"alder-unpaid","customerName":"Alder Title","signerName":"Other customer signer","date":"2026-11-01","fee":150,"paid":false},{"id":"harbor-unpaid","customerName":"Harbor Title","signerName":"Harbor unpaid signer","date":"2026-11-02","fee":225,"paid":false},{"id":"harbor-paid","customerName":"Harbor Title","signerName":"Harbor paid signer","date":"2026-11-01","fee":99,"paid":true},{"id":"harbor-cancelled","customerName":"Harbor Title","signerName":"Harbor cancelled signer","date":"2026-11-01","fee":350,"paid":false,"status":"Cancelled"},{"id":"zenith-paid","customerName":"Zenith Paid","signerName":"Paid only signer","date":"2026-11-01","fee":75,"paid":true}]"#
                        : "[]"
                }
            case "/api/expenses": responseBody = "[]"
            case "/api/credentials": responseBody = #"{"commissionNumber":null}"#
            case "/api/stripe/billing-status":
                responseBody = ProcessInfo.processInfo.arguments.contains("--billing-free")
                    ? #"{"billing":{"plan":"FREE","active":false,"isPro":false}}"#
                    : #"{"billing":{"plan":"PRO","active":true,"isPro":true,"features":{"invoiceGeneration":true}}}"#
            default: status = 404; responseBody = #"{"message":"No fixture for this request."}"#
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(responseBody.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    @MainActor static func service() -> APIService {
        let configuration = APIService.defaultSessionConfiguration()
        configuration.protocolClasses = [AuthUITestFixtures.self]
        return APIService(baseURL: "https://auth-fixtures.example.test", session: URLSession(configuration: configuration))
    }
}
#endif

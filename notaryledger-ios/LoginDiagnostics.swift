import Foundation
import OSLog

nonisolated enum LoginFailure: Error, LocalizedError, Equatable {
    case transport(Int?)
    case decoding
    case invalidResponse

    var diagnosticCode: String {
        switch self {
        case .transport(let code): code.map { "NL-NET-\(abs($0))" } ?? "NL-NET"
        case .decoding: "NL-DECODE"
        case .invalidResponse: "NL-RESPONSE"
        }
    }

    var errorDescription: String? {
        switch self {
        case .transport(URLError.timedOut.rawValue):
            "The server took too long to respond. Please try again."
        case .transport(URLError.notConnectedToInternet.rawValue):
            "You appear to be offline. Check your internet connection."
        case .transport(let code) where code.map({ (-1206 ... -1200).contains($0) || $0 == URLError.appTransportSecurityRequiresSecureConnection.rawValue }) == true:
            "A secure connection to the server could not be established."
        case .transport:
            "Could not connect to server. Please try again."
        case .decoding:
            "Login response was missing session data."
        case .invalidResponse:
            "The server returned an unexpected response."
        }
    }
}

nonisolated enum LoginDiagnostics {
    private static let logger = Logger(subsystem: "org.notaryledger.network", category: "Login")

    static func urlErrorCode(_ error: Error) -> Int? {
        let value = error as NSError
        return value.domain == NSURLErrorDomain ? value.code : nil
    }

    // Only the origin hostname and a fixed route are logged. Never pass request
    // bodies, headers, query strings, response bodies, or error descriptions here.
    static func record(host: String?, event: String, status: Int? = nil, urlError: Int? = nil) {
        let host = host ?? "unknown"
        logger.notice("host=\(host, privacy: .public) path=/api/auth/login event=\(event, privacy: .public) status=\(status ?? 0) urlError=\(urlError ?? 0)")
    }
}
